-- small binary stream library with "base 89" decoder (credit to Aero for the algorithm);
---@class QuestieStreamLib
local QuestieStreamLib = QuestieLoader:CreateModule("QuestieStreamLib");

local tinsert = table.insert

local unpack_limit = 4096 -- wow api limits unpack to somewhere between 7000-8000

-- shift level table
QSL_dltab = {};
QSL_dltab[string.byte("x")] = 0;
QSL_dltab[string.byte("y")] = 1;
QSL_dltab[string.byte("z")] = 2;

-- translation table
QSL_dttab = {};
QSL_dttab[123] = 1;
QSL_dttab[124] = 6;
QSL_dttab[125] = 59;

QSL_ltab = {};
QSL_ttab = {};
QSL_ltab[0] = "x";
QSL_ltab[1] = "y";
QSL_ltab[2] = "z";
QSL_ttab[34] = 123;
QSL_ttab[39] = 124;
QSL_ttab[92] = 125;

local StreamPool = {}

function QuestieStreamLib:GetStream(mode) -- returns a new stream
    local stream = tremove(StreamPool);
    if stream then
        return stream
    else
        stream = {}
    end
    for k,v in pairs(QuestieStreamLib) do -- copy functions to new object
        stream[k] = v
    end
    stream._pointer = 1
    stream._bin = {}
    stream._raw_bin = {}
    stream._rawptr = 1
    stream._level = 0
    stream.reset = function(self);
        self._pointer = 1
        self._bin = {}
        self._raw_bin = {}
        self._rawptr = 1
        self._level = 0
    end
    stream.finished = function(self) -- its best to call this (not required) when done using the stream
        self:reset();
        tinsert(StreamPool, self);
    end
    if mode then
        if mode == "raw" then
            stream.ReadByte = QuestieStreamLib._ReadByte_raw
            stream._WriteByte = QuestieStreamLib._WriteByte_raw
        elseif mode == "1short" then
            stream.ReadByte = QuestieStreamLib._ReadByte_1short
            stream._WriteByte = QuestieStreamLib._WriteByte_1short
        else
            stream.ReadByte = QuestieStreamLib._ReadByte_b89
            stream._WriteByte = QuestieStreamLib._WriteByte_b89
        end
    else
        stream.ReadByte = QuestieStreamLib._ReadByte_b89
        stream._WriteByte = QuestieStreamLib._WriteByte_b89
    end
    return stream
end

function QuestieStreamLib:_writeByte(val)
    self._bin[self._pointer] = val
    self._pointer = self._pointer + 1
end

function QuestieStreamLib:_readByte()
    self._pointer = self._pointer + 1
    return self._bin[self._pointer-1]
end

function QuestieStreamLib:WriteByte(val)
    self:_WriteByte(val);
    self._raw_bin[self._rawptr] = val
    self._rawptr = self._rawptr + 1
end

function QuestieStreamLib:SetPointer(pointer)
    self._pointer = pointer;
end

function QuestieStreamLib:_ReadByte_b89()
    local v = self:_readByte();
    if QSL_dltab[v] then
        self._level = QSL_dltab[v];
        v = self:_readByte();
    end
    if QSL_dttab[v] then
        return self._level * 86 + QSL_dttab[v];
    else
        return self._level * 86 + v - 33;
    end
end

function QuestieStreamLib:_WriteByte_b89(e)
    if e == nil then
        return 
    end
    local level = math.floor(e / 86);
    if not (self._level == level) then
        self._level = level
        self:_writeByte(QSL_ltab[level]);
    end
    local chr = mod(e, 86) + 33
    if QSL_ttab[chr] then
        self:_writeByte(QSL_ttab[chr]);
    else
        self:_writeByte(chr);
    end
end

local _1short_control = 237
local _1short_zero = 238

local _1short_control_table = {
    _1short_control, _1short_zero
}

local _1short_control_table_reversed = {};
for k,v in pairs(_1short_control_table) do _1short_control_table_reversed[v] = k end

function QuestieStreamLib:_WriteByte_1short(e)
    if _1short_control_table_reversed[e] then
        self:_writeByte(_1short_control);
        self:_writeByte(_1short_control_table_reversed[e]);
    elseif e == 0 then
        self:_writeByte(_1short_zero);
    else
        self:_writeByte(e);
    end
end

function QuestieStreamLib:_ReadByte_1short()
    local v = self:_readByte();
    if v == _1short_zero then
        return 0
    elseif v == _1short_control then
        v = self:_readByte();
        return _1short_control_table[v]
    else
        return v
    end
    return -1
end

function QuestieStreamLib:_WriteByte_raw(e)
    self:_writeByte(e);
end

function QuestieStreamLib:_ReadByte_raw()
    local val = string.byte(self._bin, self._pointer);
    self._pointer = self._pointer + 1
    return val
end



function QuestieStreamLib:ReadBytes(count)
    local ret = {};
    for i=1, count do
        tinsert(ret, self:ReadByte());
    end
    return unpack(ret);
end

function QuestieStreamLib:ReadShorts(count)
    local ret = {};
    for i=1, count do
        tinsert(ret, self:ReadShort());
    end
    return unpack(ret);
end

function QuestieStreamLib:ReadShort()
    return bit.lshift(self:ReadByte(), 8) + self:ReadByte();
end

function QuestieStreamLib:ReadInt()
    return bit.lshift(self:ReadByte(), 24) + bit.lshift(self:ReadByte(), 16) + bit.lshift(self:ReadByte(), 8) + self:ReadByte();
end

function QuestieStreamLib:ReadLong()
    return bit.lshift(self:ReadByte(), 56) +bit.lshift(self:ReadByte(), 48) +bit.lshift(self:ReadByte(), 40) +bit.lshift(self:ReadByte(), 32) +bit.lshift(self:ReadByte(), 24) + bit.lshift(self:ReadByte(), 16) + bit.lshift(self:ReadByte(), 8) + self:ReadByte();
end

function QuestieStreamLib:ReadTinyString()
    local length = self:ReadByte();
    local ret = {};
    for i = 1, length do
        tinsert(ret, self:ReadByte()) -- slightly better lua code is slightly better
    end
    return string.char(unpack(ret));
end

function QuestieStreamLib:ReadShortString()
    local length = self:ReadShort();
    local ret = {};
    if length > unpack_limit then
        for i = 1, length do
            tinsert(ret, string.char(self:ReadByte()));
        end
        return table.concat(ret);
    else
        for i = 1, length do
            tinsert(ret, self:ReadByte()) -- slightly better lua code is slightly better
        end
        return string.char(unpack(ret));
    end
end

function QuestieStreamLib:WriteBytes(...)
    for _,val in pairs({...}) do
        self:WriteByte(val);
    end
end

function QuestieStreamLib:WriteShorts(...)
    for _,val in pairs({...}) do
        self:WriteShort(val);
    end
end

function QuestieStreamLib:WriteShort(val)
    --print("wshort: " .. val);
    self:WriteByte(mod(bit.rshift(val, 8), 256));
    self:WriteByte(mod(val, 256));
end

function QuestieStreamLib:WriteInt(val)
    self:WriteByte(mod(bit.rshift(val, 24), 256));
    self:WriteByte(mod(bit.rshift(val, 16), 256));
    self:WriteByte(mod(bit.rshift(val, 8), 256));
    self:WriteByte(mod(val, 256));
end

function QuestieStreamLib:WriteLong(val)
    self:WriteByte(mod(bit.rshift(val, 56), 256));
    self:WriteByte(mod(bit.rshift(val, 48), 256));
    self:WriteByte(mod(bit.rshift(val, 40), 256));
    self:WriteByte(mod(bit.rshift(val, 32), 256));
    self:WriteByte(mod(bit.rshift(val, 24), 256));
    self:WriteByte(mod(bit.rshift(val, 16), 256));
    self:WriteByte(mod(bit.rshift(val, 8), 256));
    self:WriteByte(mod(val, 256));
end

function QuestieStreamLib:WriteTinyString(val)
    self:WriteByte(string.len(val));
    for i=1, string.len(val) do
        self:WriteByte(string.byte(val, i));
    end
end

function QuestieStreamLib:WriteShortString(val)
    self:WriteShort(string.len(val));
    for i=1, string.len(val) do
        self:WriteByte(string.byte(val, i));
    end
end



function QuestieStreamLib:Save()
    if self._pointer-1 > unpack_limit then
        for i=1,self._pointer-1 do
            self._bin[i] = string.char(self._bin[i]);
        end
        return table.concat(self._bin);
    end
    return string.char(unpack(self._bin));
end

function QuestieStreamLib:SaveRaw()
    if self._rawptr-1 > unpack_limit then
        for i=1,self._rawptr-1 do
            self._raw_bin[i] = string.char(self._raw_bin[i]);
        end
        return table.concat(self._raw_bin);
    end
    return string.char(unpack(self._raw_bin));
end

function QuestieStreamLib:Load(bin)
    self._pointer = 1
    self._bin = {string.byte(bin, 1, -1)}
    self._level = 0
end

function QuestieStreamLib:LoadRaw(bin)
    self._pointer = 1
    self._bin = bin
    self._level = 0
end
