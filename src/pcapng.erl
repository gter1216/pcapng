-module(pcapng).

-export([decode_init/0, decode_init/1, decode_finished/1, decode/2, encode/1]).

-compile(bin_opt_info).
-compile(inline).
-compile({inline,[decode_block/3, decode_options/3, decode_options/5]}).


-define(UINT16(X), uint16(X, ByteOrder)).
-define(UINT32(X), uint32(X, ByteOrder)).
-define(UINT64(X), uint64(X, ByteOrder)).

decode_init() ->
    {init, undefined, <<>>}.
decode_init(Data) ->
    decode_first(Data).

decode_finished({_, undefined, <<>>}) ->
    true;
decode_finished({_, 0, <<>>}) ->
    true;
decode_finished(_) ->
    false.

decode(Data, {init, _, OldData}) ->
    decode_first(<<OldData/binary, Data/binary>>);
decode(NewData, {ByteOrder,SectionLength, OldData}) ->
    decode_next(ByteOrder, SectionLength, <<OldData/binary, NewData/binary>>, []).

decode_first(Data) ->
    decode_next_shb(Data, []).

encode(_Data) ->
    ok.

decode_option(0, <<>>, _, _) ->
    [];
decode_option(1, Value, _, _) ->
    {comment, Value};
decode_option(Code, Value, ByteOrder, Fun = undefined) ->
    error(badarg, [Code, Value, ByteOrder, Fun]);
decode_option(Code, Value, ByteOrder, Fun) ->
    Fun(Code, Value, ByteOrder).

decode_options(Code, Length, Data, ByteOrder, Fun)
  when byte_size(Data) >= Length ->
    PadLength = pad_length(4, Length),
    <<Option:Length/bytes, _Pad:PadLength/bytes, Rest/binary>> = Data,
    {decode_option(Code, Option, ByteOrder, Fun), Rest}.

decode_options(<<Code:16/little-integer, Length:16/little-integer, Data/binary>>, little, Fun) ->
    decode_options(Code, Length, Data, little, Fun).

decode_options(<<>>, _, _, Acc) ->
    lists:reverse(Acc);
decode_options(Data, ByteOrder, Fun, Acc) ->
	case decode_options(Data, ByteOrder, Fun) of
	    {[], <<>>} ->
		lists:reverse(Acc);
	    {Opt, Next} ->
		decode_options(Next, ByteOrder, Fun, [Opt|Acc])
	end.

sectionlength(16#ffffffffffffffff) ->
    undefined;
sectionlength(X) ->
    X.

decode_shb_option(2, Value, _) ->
    {hardware, Value};
decode_shb_option(3, Value, _) ->
    {os, Value};
decode_shb_option(4, Value, _) ->
    {userappl, Value};
decode_shb_option(Code, Value, ByteOrder) ->
    error(badarg, [Code, Value, ByteOrder]).

sectionlength_sub(undefined, _) ->
    undefined;
sectionlength_sub(SectionLength, Length) ->
    SectionLength - Length.

decode_shb(<<16#0a0d0d0a:32, Length:32/bits, ByteOrderMagic:32/bits,
	     Major:16/bits, Minor:16/bits,
	     SectionLength:64/bits, Rest/binary>>) ->
    ByteOrder = case ByteOrderMagic of
		    <<16#1a2b3c4d:32/little-integer>> ->
			little;
		    <<16#1a2b3c4d:32/big-integer>> ->
			big
		end,
    decode_shb(?UINT32(Length) - 28, Rest, ByteOrder, ?UINT16(Major), ?UINT16(Minor), ?UINT64(SectionLength)).

decode_shb(Length, Data, ByteOrder, Major, Minor, SectionLength)
  when byte_size(Data) >= Length ->
    case Data of
	<<PayLoad:Length/bytes, _BLength:32/bits, NextBlock/binary>> ->
	    SHB = {shb, {Major, Minor}, decode_options(PayLoad, ByteOrder, fun decode_shb_option/3, [])},
	    {ByteOrder, sectionlength(SectionLength), SHB, NextBlock};
	_ ->
	    error(badarg, [Length, Data, ByteOrder, Major, Minor, SectionLength])
    end.

ifd_code(name)		-> 2;
ifd_code(description)	-> 3;
ifd_code('IPv4addr')	-> 4;
ifd_code('IPv6addr')	-> 5;
ifd_code('MACaddr')	-> 6;
ifd_code('EUIaddr')	-> 7;
ifd_code(speed)		-> 8;
ifd_code(tsresol)	-> 9;
ifd_code(tzone)		-> 10;
ifd_code(filter)	-> 11;
ifd_code(os)		-> 12;
ifd_code(fcslen)	-> 13;
ifd_code(tsoffset)	-> 14;

ifd_code(2)	-> name;
ifd_code(3)	-> description;
ifd_code(4)	-> 'IPv4addr';
ifd_code(5)	-> 'IPv6addr';
ifd_code(6)	-> 'MACaddr';
ifd_code(7)	-> 'EUIaddr';
ifd_code(8)	-> speed;
ifd_code(9)	-> tsresol;
ifd_code(10)	-> tzone;
ifd_code(11)	-> filter;
ifd_code(12)	-> os;
ifd_code(13)	-> fcslen;
ifd_code(14)	-> tsoffset;

ifd_code(X) when is_integer(X) -> X.

epb_code(flags)		-> 2;
epb_code(hash)		-> 3;
epb_code(dropcount)	-> 4;

epb_code(2)	-> flags;
epb_code(3)	-> hash;
epb_code(4)	-> dropcount;

epb_code(X) when is_integer(X) -> X.

nrb_code(dnsname)	-> 2;
nrb_code(dnsIP4addr)	-> 3;
nrb_code(dnsIP6addr)	-> 4;

nrb_code(2)	-> dnsname;
nrb_code(3)	-> dnsIP4addr;
nrb_code(4)	-> dnsIP6addr;

nrb_code(X) when is_integer(X) -> X.

isb_code(starttime)	-> 2;
isb_code(endtime)	-> 3;
isb_code(ifrecv)	-> 4;
isb_code(ifdrop)	-> 5;
isb_code(filteraccept)	-> 6;
isb_code(osdrop)	-> 7;
isb_code(usrdeliv)	-> 8;

isb_code(2)	-> starttime;
isb_code(3)	-> endtime;
isb_code(4)	-> ifrecv;
isb_code(5)	-> ifdrop;
isb_code(6)	-> filteraccept;
isb_code(7)	-> osdrop;
isb_code(8)	-> usrdeliv;

isb_code(X) when is_integer(X) -> X.

decode_ifd_option(Code, Value, _ByteOrder) when Code =< 14 ->
    {ifd_code(Code), Value};
decode_ifd_option(Code, Value, ByteOrder) ->
    error(badarg, [Code, Value, ByteOrder]).

decode_epb_option(Code, Value, _ByteOrder) when Code =< 4 ->
    {epb_code(Code), Value};
decode_epb_option(Code, Value, ByteOrder) ->
    error(badarg, [Code, Value, ByteOrder]).

decode_nrb_option(Code, Value, _ByteOrder) when Code =< 4 ->
    {nrb_code(Code), Value};
decode_nrb_option(Code, Value, ByteOrder) ->
    error(badarg, [Code, Value, ByteOrder]).

decode_isb_option(Code, Value, _ByteOrder) when Code =< 8 ->
    {isb_code(Code), Value};
decode_isb_option(Code, Value, ByteOrder) ->
    error(badarg, [Code, Value, ByteOrder]).

decode_pb(InterfaceId, DropsCount, TStampHigh, TStampLow, CaptureLen, PacketLen, Data, ByteOrder) ->
    PadLength = pad_length(4, CaptureLen),
    case Data of
	<<PacketData:CaptureLen/bytes>> ->
	    %% no padding, this seems to violate Section 3.5, but wireshark accepts these frames
	    %% don't care much, since Packet Blocks are obsoleted
	    {pb, InterfaceId, DropsCount, {TStampHigh, TStampLow}, PacketLen, [], PacketData};
	<<PacketData:CaptureLen/bytes, _Pad:PadLength/bytes, Options/binary>> ->
	    {pb, InterfaceId, DropsCount, {TStampHigh, TStampLow}, PacketLen, decode_options(Options, ByteOrder, fun decode_epb_option/3, []), PacketData};
	_ ->
	    error(badarg, [InterfaceId, DropsCount, TStampHigh, TStampLow, CaptureLen, PacketLen, Data, ByteOrder])
    end.

decode_spb(PacketLen, Data, _)
  when byte_size(Data) > PacketLen ->
    <<Packet:PacketLen/bytes, _Pad/binary>> = Data,
    {spb, PacketLen, Packet};
decode_spb(PacketLen, Data, _) ->
    {spb, PacketLen, Data}.

decode_nrb_record(0, <<>>, <<>>, _, Acc) ->
    lists:reverse(Acc);
decode_nrb_record(1, <<IP:4/bytes, Names/binary>>, NextRecord, ByteOrder, Acc) ->
    Record = {ipv4, IP, binary:split(Names, <<0>>, [global, trim])},
    decode_nrb_records(NextRecord, ByteOrder, [Record|Acc]);
decode_nrb_record(2, <<IP:16/bytes, Names/binary>>, NextRecord, ByteOrder, Acc) ->
    Record = {ipv6, IP, binary:split(Names, <<0>>, [global, trim])},
    decode_nrb_records(NextRecord, ByteOrder, [Record|Acc]);
decode_nrb_record(Type, Value, NextRecord, ByteOrder, Acc) ->
    error(badarg, [Type, Value, NextRecord, ByteOrder, Acc]).

decode_nrb_records(Type, Length, Data, ByteOrder, Acc)
  when byte_size(Data) >= Length ->
    PadLength = pad_length(4, Length),
    <<Value:Length/bytes, _Pad:PadLength/binary, NextRecord/binary>> = Data,
    decode_nrb_record(Type, Value, NextRecord, ByteOrder, Acc);
decode_nrb_records(Type, Length, Data, ByteOrder, Acc) ->
    error(badarg, [Type, Length, Data, ByteOrder, Acc]).

decode_nrb_records(<<Type:16/bits, Length:16/bits, Data/binary>>, ByteOrder, Acc) ->
    decode_nrb_records(?UINT16(Type), ?UINT16(Length), Data, ByteOrder, Acc);
decode_nrb_records(Data, ByteOrder, Acc) ->
    error(badarg, [Data, ByteOrder, Acc]).

decode_epb(InterfaceId, TStampHigh, TStampLow, CaptureLen, PacketLen, Data, ByteOrder)
  when byte_size(Data) >= CaptureLen ->
    PadLength = pad_length(4, CaptureLen),
    <<PacketData:CaptureLen/bytes, _Pad:PadLength/bytes, Options/binary>> = Data,
    {epb, InterfaceId, {TStampHigh, TStampLow}, PacketLen, decode_options(Options, ByteOrder, fun decode_epb_option/3, []), PacketData};
decode_epb(InterfaceId, TStampHigh, TStampLow, CaptureLen, PacketLen, Data, ByteOrder) ->
    error(badarg, [InterfaceId, TStampHigh, TStampLow, CaptureLen, PacketLen, Data, ByteOrder]).

decode_block_payload(1, <<LinkType:16/bits, _Reserved:16/bits, SnapLen:32/bits, Options/binary>>, ByteOrder) ->
    {ifd, ?UINT16(LinkType), ?UINT32(SnapLen), decode_options(Options, ByteOrder, fun decode_ifd_option/3, [])};
decode_block_payload(2, <<InterfaceId:16/bits, DropsCount:16/bits,
			  TStampHigh:32/bits, TStampLow:32/bits,
			  CaptureLen:32/bits, PacketLen:32/bits, Data/binary>>, ByteOrder) ->
    decode_pb(?UINT16(InterfaceId), ?UINT16(DropsCount), ?UINT32(TStampHigh), ?UINT32(TStampLow),
	      ?UINT32(CaptureLen), ?UINT32(PacketLen), Data, ByteOrder);
decode_block_payload(3, <<PacketLen:32/bits, Data/binary>>, ByteOrder) ->
    decode_spb(?UINT32(PacketLen), Data, ByteOrder);
decode_block_payload(4, Data, ByteOrder) ->
    {Records, Options} = decode_nrb_records(Data, ByteOrder, []),
    {nrb, Records, decode_options(Options, ByteOrder, fun decode_nrb_option/3, [])};
decode_block_payload(5, <<InterfaceId:32/bits, TStampHigh:32/bits, TStampLow:32/bits,
			  Options/binary>>, ByteOrder) ->
    {isb, ?UINT32(InterfaceId), ?UINT32(TStampHigh), ?UINT32(TStampLow),
     decode_options(Options, ByteOrder, fun decode_isb_option/3, [])};
decode_block_payload(6, <<InterfaceId:32/bits, TStampHigh:32/bits, TStampLow:32/bits,
			  CaptureLen:32/bits, PacketLen:32/bits, Data/binary>>, ByteOrder) ->
    decode_epb(?UINT32(InterfaceId), ?UINT32(TStampHigh), ?UINT32(TStampLow),
	       ?UINT32(CaptureLen), ?UINT32(PacketLen), Data, ByteOrder);
decode_block_payload(Type, PayLoad, _ByteOrder) ->
    {Type, PayLoad}.

decode_block(Type, Length, Data, ByteOrder, SectionLength) ->
    PayLoadLen = Length - 12,
    case Data of
	<<PayLoad:PayLoadLen/bytes, BLength:32/bits, Next/binary>> ->
	    Block = decode_block_payload(Type, PayLoad, ByteOrder),
	    {Block, sectionlength_sub(SectionLength, Length), Next};
	_ ->
	    error(badarg, [Type, Length, Data, ByteOrder, SectionLength])
    end.

decode_block(<<16#0a0d0d0a:32, _/binary>>, _, undefined) ->
    shb;
decode_block(Data = <<16#0a0d0d0a:32, _/binary>>, ByteOrder, SectionLength) ->
    %% unexpected SHB
    error(badarg, [Data, ByteOrder, SectionLength]);

decode_block(<<Type:32/bits, Length:32/bits, Rest/bits>>, ByteOrder, SectionLength) ->
    %% from wireshark source:
    %%    add padding bytes to "block total length"
    %%    (the "block total length" of some example files don't contain the packet data padding bytes!)
    Len = ?UINT32(Length),
    FixedLen = Len + pad_length(4, Len),
    decode_block(?UINT32(Type), FixedLen, Rest, ByteOrder, SectionLength);
decode_block(_, _, _) ->
    need_more_data.

return_decode(ByteOrder, SectionLength, Data, Acc) ->
    State = {ByteOrder, SectionLength, Data},
    Blocks = lists:reverse(Acc),
    {Blocks, State}.

decode_next_shb(Data, Acc) ->
    case decode_shb(Data) of
	{ByteOrder, SectionLength, SHB, Next} ->
	    decode_next(ByteOrder, SectionLength, Next, [SHB|Acc]);
	need_mode_data ->
	    State = {init, undefined, Data},
	    {[], State}
    end.

decode_next(ByteOrder, SectionLength, <<>>, Acc) ->
    return_decode(ByteOrder, SectionLength, <<>>, Acc);
decode_next(ByteOrder, SectionLength, Data, Acc) ->
    case decode_block(Data, ByteOrder, SectionLength) of
	need_more_data ->
	    return_decode(ByteOrder, SectionLength, Data, Acc);
	shb ->
	    decode_next_shb(Data, Acc);
	{Block, 0, <<>>} ->
	    return_decode(ByteOrder, 0, <<>>, [Block|Acc]);
	{Block, 0, NextBlock} ->
	    decode_next_shb(NextBlock, [Block|Acc]);
	{Block, NewSectionLength, NextBlock} ->
	    decode_next(ByteOrder, NewSectionLength, NextBlock, [Block|Acc])
    end.
	
%%%===================================================================
%%% Internal functions
%%%===================================================================

pad_length(Width, Length) ->
    (Width - Length rem Width) rem Width.

uint16(<<Value:16/little-integer>>, little) ->
    Value;
uint16(<<Value:16/big-integer>>, big) ->
    Value.
uint32(<<Value:32/little-integer>>, little) ->
    Value;
uint32(<<Value:32/big-integer>>, big) ->
    Value.
uint64(<<Value:64/little-integer>>, little) ->
    Value;
uint64(<<Value:64/big-integer>>, big) ->
    Value.
