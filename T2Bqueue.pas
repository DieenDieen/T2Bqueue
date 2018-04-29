unit T2Bqueue;

interface

procedure cpupause;assembler;register;

type

 IQueue<T> = interface(IInterface)
    procedure Clear();
    procedure Enqueue(const AValue: T);
    function TryDequeue(out entry:T): Boolean;
    function Empty(): Boolean;
  end;

const DefaultCache=1024;
type
TLinkedQueue<T> = class(TInterfacedObject,IQueue<T>)
  protected type
    PEntry = ^TEntry;
    TEntry = record
      FNext: PEntry;
      Fvalue:T;
    end;
  protected var
    FHead, FLast: PEntry;
    { Caching }
    fEntryCache:array[0..DefaultCache-1] of PEntry;
    cacheRead,cacheWrite:Cardinal;
    function NeedEntry: PEntry;inline;
    function AllocNewEntry: PEntry;inline;
    procedure ReleaseEntry(const AEntry: PEntry);
  public
    constructor Create(); overload;
    destructor Destroy(); override;
    procedure Clear();

    procedure Enqueue(const AValue: T);inline;

    function TryDequeue(out entry:T): Boolean;inline;
    function Empty(): Boolean;inline;
    function NotEmpty(): Boolean;inline;
  end;

implementation
{ TLinkedQueue<T> }


constructor TLinkedQueue<T>.Create;
var Entry:PEntry;
   i:integer;
begin
  inherited;
  for i := Low(fEntryCache) to High(fEntryCache) do fEntryCache[i] := nil;
  cacheRead := Low(fEntryCache); cacheWrite:= High(fEntryCache) div 2;
  for i := cacheRead to cacheWrite-1 do fEntryCache[i] := AllocNewEntry;
  FHead := AllocNewEntry;
  FHead^.FNext := nil;
  FLast := FHead;
end;

function TLinkedQueue<T>.Empty: Boolean;
begin
  Result := FHead = fLast;
end;

function TLinkedQueue<T>.NotEmpty: Boolean;
begin
   result := not empty;
end;


procedure TLinkedQueue<T>.Clear;
var value:T;
begin
  while notEmpty do TryDequeue(value);
end;

procedure cpupause;assembler;register;
asm
   pause
end;

procedure TLinkedQueue<T>.Enqueue(const AValue: T);
var
  LNew: PEntry;
  succed:Boolean;
    mycnt:integer;
begin
  LNew := NeedEntry;
  LNew^.Fvalue := AValue;
  LNew^.FNext := LNew;
  mycnt := 0;
  AtomicCmpExchange(FLast^.FNext,LNew,Nil,succed);
  while not succed do
     begin
       cpupause;
       AtomicCmpExchange(FLast^.FNext,LNew,Nil,succed);
      
     end;
  FLast := LNew;
  LNew^.FNext := nil;
end;

function TLinkedQueue<T>.TryDequeue(out entry:T): Boolean;
var
  LOut: PEntry;
  succed:Boolean;
  mycnt:integer;
  head:PEntry;
begin
  Result := False;
  head := fHead;
  if FLast=Head then exit;
  LOut :=Head^.FNext;
  if (LOut=nil) and (FLast<>Head) then
    FLast:=Head; // this shouldn't happen
  if LOut<>nil then
  begin
     succed := False;
     mycnt := 16;
     repeat
        if LOut=nil then exit;
      	if LOut^.FNext=LOut then
           exit
           else
          LOut := AtomicCmpExchange(Head^.FNext,LOut^.FNext,LOut,succed);
          if not succed then
             begin
             for mycnt:=1 to mycnt do cpupause;
             if mycnt<1024 then mycnt:=mycnt *2;
             end;
     until succed;
     while FLast=LOut do
        AtomicCmpExchange(FLast,Head,LOut);  //check if it was last element
     LOut^.FNext := Lout;
     Entry := LOut^.Fvalue;
     ReleaseEntry(LOut);
     Result := True;
  end;
end;

function TLinkedQueue<T>.AllocNewEntry: PEntry;
   begin
      Result := AllocMem(SizeOf(TEntry));
      Result^.Fvalue := default(T);
      Result^.FNext := Result;
   end;

function TLinkedQueue<T>.NeedEntry: PEntry;
var succed:Boolean;
   cw,cr,Re:cardinal;
begin
   succed :=false;
   Result := fEntryCache[cacheRead mod DefaultCache];

   if (Result<>nil) and ((cacheRead+DefaultCache div 16)<cacheWrite) then
      begin
      Result := AtomicCmpExchange(fEntryCache[cacheRead mod DefaultCache],nil,Result,succed);
      if succed then
         AtomicIncrement (cacheRead)
      end;
   if not succed then
      Result := AllocNewEntry;
  { Initialize the node }
  Result^.Fvalue := default(T);
  Result^.FNext := Result;
end;

procedure TLinkedQueue<T>.ReleaseEntry(const AEntry: PEntry);
var succed:Boolean;
begin
    AEntry^.FNext := AEntry;
    AEntry^.Fvalue := default(T);  // this should help ref counted items
    AtomicCmpExchange(fEntryCache[cacheWrite mod DefaultCache],AEntry,nil,succed);
    if succed then
       AtomicIncrement(cacheWrite)
       else
       FreeMem(AEntry);
end;

destructor TLinkedQueue<T>.Destroy;
var i:integer;
begin
  Clear();
  ReleaseEntry(FHead);
  for i := Low(fEntryCache) to High(fEntryCache) do
     if fEntryCache[i]<> nil then
        begin
        fEntryCache[i]^.Fvalue := default(T);
        FreeMem(fEntryCache[i]);
        fEntryCache[i]:= nil
        end;
  inherited;
end;


end.
