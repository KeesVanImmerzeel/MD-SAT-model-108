library dsmodel108;
  {-Sulfaat S-belasting (conservatief, kg S/ha/jaar) }

  { Important note about DLL memory management: ShareMem must be the
  first unit in your library's USES clause AND your project's (select
  Project-View Source) USES clause if your DLL exports any procedures or
  functions that pass strings as parameters or function results. This
  applies to all strings passed to and from your DLL--even those that
  are nested in records and classes. ShareMem is the interface unit to
  the BORLNDMM.DLL shared memory manager, which must be deployed along
  with your DLL. To avoid using BORLNDMM.DLL, pass string information
  using PChar or ShortString parameters. }
uses
  ShareMem,
  windows, SysUtils, Classes, LargeArrays, ExtParU, USpeedProc, uDCfunc,UdsModel, UdsModelS,
  xyTable, DUtils, uError;

Const
  cModelID      = 108;  {-Uniek modelnummer}

  {-Beschrijving van de array met afhankelijke variabelen}
  cNrOfDepVar   = 2;  {-Lengte van de array met afhankelijke variabelen}
  cNN           = 1;  {-Natuurlijk neerslagoverschot (m/jaar)}
  cS            = 2;  {-Sulfaat S-belasting (kg S/ha/jaar)}

  {-Aantal keren dat een discontinuiteitsfunctie wordt aangeroepen in de procedure met
    snelheidsvergelijkingen (DerivsProc)}
  nDC = 0;
  
  {-Variabelen die samenhangen met het aanroepen van het model vanuit de Shell}
  cnRP    = 4;   {-Aantal RP-tijdreeksen die door de Shell moeten worden aange-
                   leverd (in de externe parameter Array EP (element EP[ indx-1 ]))}
  cnSQ    = 0;   {-Idem punt-tijdreeksen}
  cnRQ    = 0;   {-Idem lijn-tijdreeksen}

  {-Beschrijving van het eerste element van de externe parameter-array (EP[cEP0])}
  cNrXIndepTblsInEP0  = 4;  {-Aantal XIndep-tables in EP[cEP0]}
  cNrXdepTblsInEP0    = 0;  {-Aantal Xdep-tables   in EP[cEP0]}
  {-Nummering van de xIndep-tabellen in EP[cEP0]. De nummers 0&1 zijn gereserveerd}
  cTb_MinMaxValKeys   = 2;
  cTb_ConvFact        = 3;

  {-Beschrijving van het tweede element van de externe parameter-array (EP[cEP1])}
  {-Opmerking: table 0 van de xIndep-tabellen is gereserveerd}
  {-Nummering van de xdep-tabellen in EP[cEP1]}
  cTb_NN          = 0;  {-Natuurlijke grondwateraanvulling (m/jr)}
  cTb_S_Depositie = 1;  {-Atmosferische depositie (kg S/ha/jaar)}
  cTb_Landgebruik = 2;  {-Landgebruik}
  cTb_S_ref       = 3;  {-Referentie Sulfaat S-belasting (kg S/ha/jaar)}

  {-Model specifieke fout-codes}
  cInvld_NN          = -9700;
  cInvld_S_Depositie = -9701;
  cInvld_Landgebruik = -9702;
  cInvld_S_ref       = -9703;

var
  Indx: Integer; {-Door de Boot-procedure moet de waarde van deze index worden ingevuld,
                   zodat de snelheidsprocedure 'weet' waar (op de externe parameter-array)
				   hij zijn gegevens moet zoeken}
  ModelProfile: TModelProfile;
                 {-Object met met daarin de status van de discontinuiteitsfuncties
				   (zie nDC) }
  {-Geldige range van key-/parameter/initiele waarden. De waarden van deze  variabelen moeten
    worden ingevuld door de Boot-procedure}
  cMin_Landgebruik, cMax_Landgebruik: Integer;
  cMin_NN, cMin_S_Depositie, cMin_S_ref,
  cMax_NN, cMax_S_Depositie, cMax_S_ref: Double;
Procedure MyDllProc( Reason: Integer );
begin
  if Reason = DLL_PROCESS_DETACH then begin {-DLL is unloading}
    {-Cleanup code here}
	if ( nDC > 0 ) then
      ModelProfile.Free;
  end;
end;

Procedure DerivsProc( var x: Double; var y, dydx: TLargeRealArray;
                      var EP: TExtParArray; var Direction: TDirection;
                      var Context: Tcontext; var aModelProfile: PModelProfile; var IErr: Integer );
{-Deze procedure verschaft de array met afgeleiden 'dydx',
  gegeven het tijdstip 'x' en
  de toestand die beschreven wordt door de array 'y' en
  de externe condities die beschreven worden door de 'external parameter-array EP'.
  Als er geen fout op is getreden bij de berekening van 'dydx' dan wordt in deze procedure
  de variabele 'IErr' gelijk gemaakt aan de constante 'cNoError'.
  Opmerking: in de array 'y' staan dus de afhankelijke variabelen, terwijl 'x' de
  onafhankelijke variabele is}
var
  Landgebruik: Integer;   {-Sleutel-waarden voor de default-tabellen in EP[cEP0]}
  NN, S_Depositie, S_ref, {-Parameter-waarden afkomstig van de Shell}
  ConvFact,               {-Default parameter-waarden in EP[cEP0]}
  S_Landgebruik: Double;  {-Afgeleide (berekende) parameter-waarden}
  i: Integer;

Function SetKeyAndParValues( var IErr: Integer ): Boolean;

  Function GetLandgebruik( const x: Double ): Integer;
  begin
    with EP[ indx-1 ].xDep do
      Result := Trunc( Items[ cTb_Landgebruik ].EstimateY( x, Direction ) );
  end;

  Function GetNN( const x: Double ): Double;
  begin
    with EP[ indx-1 ].xDep do
      Result := Items[ cTb_NN ].EstimateY( x, Direction );
  end;

  Function GetS_Depositie( const x: Double ): Double;
  begin
    with EP[ indx-1 ].xDep do
      Result := Items[ cTb_S_Depositie ].EstimateY( x, Direction );
  end;

  Function GetS_ref( const x: Double ): Double;
  begin
    with EP[ indx-1 ].xDep do
      Result := Items[ cTb_S_ref ].EstimateY( x, Direction );
  end;

  Function GetConvFact( const Landgebruik: Integer ): Double;
  begin
    with EP[ cEP0 ].xInDep.Items[ cTb_ConvFact ] do
      Result := GetValue( 1, Landgebruik ); {row, column}
  end;

begin {-Function SetKeyAndParValues}
  Result := False;

  Landgebruik := GetLandgebruik( x );
  if ( Landgebruik < cMin_Landgebruik ) or ( Landgebruik > cMax_Landgebruik ) then begin
    IErr := cInvld_Landgebruik; Exit;
  end;
  
  NN := GetNN( x );
  if ( NN < cMin_NN ) or ( NN > cMax_NN ) then begin
    IErr := cInvld_NN; Exit;
  end;

  S_Depositie := GetS_Depositie( x );
  if ( S_Depositie < cMin_S_Depositie ) or ( S_Depositie > cMax_S_Depositie ) then begin
    IErr := cInvld_S_Depositie; Exit;
  end;

  S_ref := GetS_ref( x );
  if ( S_ref < cMin_S_ref ) or ( S_ref > cMax_S_ref ) then begin
    IErr := cInvld_S_ref; Exit;
  end;

  ConvFact := GetConvFact( Landgebruik );

  S_Landgebruik := ConvFact * S_ref;

  Result := True;
end; {-Function SetKeyAndParValues}

begin

  IErr := cUnknownError;
  for i := 1 to cNrOfDepVar do {-Default speed = 0}
    dydx[ i ] := 0;

  {-Geef de aanroepende procedure een handvat naar het ModelProfiel}
  if ( nDC > 0 ) then
    aModelProfile := @ModelProfile
  else
    aModelProfile := NIL;

  if ( Context = UpdateYstart ) then begin {-Run fase 1}

    if ( indx = cBoot2 ) then
      ScaleTimesFromShell( cFromDayToYear, EP );

    IErr := cNoError;
  end else begin {-Run fase 2}            

    if not SetKeyAndParValues( IErr ) then 
      exit;

    {-Bereken de array met afgeleiden 'dydx'}
    dydx[ cNN ] := NN;
    dydx[ cS ]  := S_Depositie + S_Landgebruik;
  end;
end; {-DerivsProc}

Function DefaultBootEP( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Initialiseer de meest elementaire gegevens van het model. Shell-gegevens worden door deze
    procedure NIET verwerkt}
Procedure SetMinMaxKeyAndParValues;
begin
  with EP[ cEP0 ].xInDep.Items[ cTb_MinMaxValKeys ] do begin
    cMin_NN          :=        GetValue( 1, 1 );
    cMax_NN          :=        GetValue( 1, 2 );
    cMin_S_Depositie :=        GetValue( 1, 3 );
    cMax_S_Depositie :=        GetValue( 1, 4 );
    cMin_Landgebruik := Trunc( GetValue( 1, 5 ) ); {rij, kolom}
    cMax_Landgebruik := Trunc( GetValue( 1, 6 ) );
    cMin_S_ref       :=        GetValue( 1, 7 );
    cMax_S_ref       :=        GetValue( 1, 8 );
  end;
end;
Begin
  Result := DefaultBootEPFromTextFile( EpDir, BootEpArrayOption, cModelID, cNrOfDepVar, nDC, cNrXIndepTblsInEP0,
                                       cNrXdepTblsInEP0, Indx, EP );
  if ( Result = cNoError ) then
    SetMinMaxKeyAndParValues;
end;

Function TestBootEP( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Deze boot-procedure verwerkt alle basisgegevens van het model en leest de Shell-gegevens
    uit een bestand. Na initialisatie met deze boot-procedure is het model dus gereed om
	'te draaien'. Deze procedure kan dus worden gebruikt om het model 'los' van de Shell te
	testen}
Begin
  Result := DefaultBootEP( EpDir, BootEpArrayOption, EP );
  if ( Result <> cNoError ) then
    exit;
  Result := DefaultTestBootEPFromTextFile( EpDir, BootEpArrayOption, cModelID, cnRP + cnSQ + cnRQ, Indx, EP );
  if ( Result <> cNoError ) then
    exit;
  SetReadyToRun( EP);
end;

Function BootEPForShell( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Deze procedure maakt het model gereed voor Shell-gebruik.
    De xDep-tables in EP[ indx-1 ] worden door deze procedure NIET geinitialiseerd omdat deze
	gegevens door de Shell worden verschaft }
begin
  Result := DefaultBootEP( EpDir, cBootEPFromTextFile, EP );
  if ( Result = cNoError ) then
    Result := DefaultBootEPForShell( cnRP, cnSQ, cnRQ, Indx, EP );
end;

Exports DerivsProc       index cModelIndxForTDSmodels, {999}
        DefaultBootEP    index cBoot0, {1}
        TestBootEP       index cBoot1, {2}
        BootEPForShell   index cBoot2; {3}

begin
  {-Dit zgn. 'DLL-Main-block' wordt uitgevoerd als de DLL voor het eerst in het geheugen wordt
    gezet (Reason = DLL_PROCESS_ATTACH)}
  DLLProc := @MyDllProc;
  Indx := cBootEPArrayVariantIndexUnknown;
  if ( nDC > 0 ) then
    ModelProfile := TModelProfile.Create( nDC );  
end.
