---@class QuestieComms
local QuestieComms = QuestieLoader:CreateModule("QuestieComms");
-------------------------
--Import modules.
-------------------------
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest");
---@type QuestieEventHandler
local QuestieEventHandler = QuestieLoader:ImportModule("QuestieEventHandler");
---@type QuestieSerializer
local QuestieSerializer = QuestieLoader:ImportModule("QuestieSerializer");
---@type QuestieCompress
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib");
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer");
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");

local _QuestieComms = {...};
-- Addon message prefix
_QuestieComms.prefix = "questie";
-- List of all players questlog private to prevent modification from the outside.
QuestieComms.remoteQuestLogs = {};

-- The idea here is that all messages with the same "base number" are compatible
-- New message versions increase the number by 0.1, and if the message becomes "incompatible" you increase with 1
-- Say if the message is 1.5 it is valid as long as it is < 2. If it is 2.5 it is not compatible for example.
local commMessageVersion = 5.0;

local warnedUpdate = false;
local suggestUpdate = true;

--Not used, contains a list of hashes for quest, used to compare change.
--_QuestieComms.questHashes = {};

--Channel types
_QuestieComms.QC_WRITE_ALLGUILD = "GUILD"
_QuestieComms.QC_WRITE_ALLGROUP = "PARTY"
_QuestieComms.QC_WRITE_ALLRAID = "RAID"
_QuestieComms.QC_WRITE_WHISPER = "WHISPER"
_QuestieComms.QC_WRITE_CHANNEL = "CHANNEL"

--Message types.
_QuestieComms.QC_ID_BROADCAST_QUEST_UPDATE = 1 -- send quest_log_update status to party/raid members
_QuestieComms.QC_ID_BROADCAST_QUEST_REMOVE = 2 -- send quest remove status to party/raid members

_QuestieComms.QC_ID_BROADCAST_FULL_QUESTLIST = 10
_QuestieComms.QC_ID_REQUEST_FULL_QUESTLIST = 11


-- NOT USED
-- stringLookup it built from idLookup!
_QuestieComms.stringLookup = {}
_QuestieComms.idLookup = {
    ["id"] = 1,
    ["type"] = 2,
    ["finished"] = 3,
    ["fulfilled"] = 4,
    ["required"] = 5,
}
for string, int in pairs(_QuestieComms.idLookup) do
    _QuestieComms.stringLookup[int] = string;
end
-- !NOT USED

--- Global Functions --


---------
-- Fetch quest information about a specific player.
-- Params:
--  questId (int);
--  playerName (string) OPTIONAL
-- Return:
--  Similar object as QuestieQuest:GetRawLeaderBoardDetails();
--  Quest.(Id|level|isComplete) --title is trimmed to save space
--  Quest.Objectives[index].(description|objectiveType|isCompleted);
---------
--Only questid gets all players with that quest and their progress
--Both name and questid returns a specific players progress if one exist.
function QuestieComms:GetQuest(questId, playerName)
  if(QuestieComms.remoteQuestLogs[questId]) then
    if(playerName) then
        if(QuestieComms.remoteQuestLogs[questId][playerName]) then
            -- Create a copy of the object, other side should never be able to edit the underlying object.
            local quest = {};
            for key,value in pairs(QuestieComms.remoteQuestLogs[questId][playerName]) do
                quest[key] = value;
            end
            return quest;
        end
    else
        -- Create a copy of the object, other side should never be able to edit the underlying object.
        local quest = {};
        for playerName, objectivesData in pairs(QuestieComms.remoteQuestLogs[questId]) do
            quest[playerName] = objectivesData;
        end
        return quest;
    end
  end
  return nil;
end

function QuestieComms:Initialize()
  -- Lets us send any length of message. Also implements ChatThrottleLib to not get disconnected.
  Questie:RegisterComm(_QuestieComms.prefix, _QuestieComms.OnCommReceived);

  -- Events to be used to broadcast updates to other people
  Questie:RegisterMessage("QC_ID_BROADCAST_QUEST_UPDATE", _QuestieComms.BroadcastQuestUpdate);
  Questie:RegisterMessage("QC_ID_BROADCAST_QUEST_REMOVE", _QuestieComms.BroadcastQuestRemove);

  -- Bucket for 2 seconds to prevent spamming.
  Questie:RegisterBucketMessage("QC_ID_BROADCAST_FULL_QUESTLIST", 2, _QuestieComms.BroadcastQuestLog);

  -- Responds to the "hi" event from others.
  Questie:RegisterMessage("QC_ID_REQUEST_FULL_QUESTLIST", _QuestieComms.RequestQuestLog);

  QuestieEventHandler:GROUP_JOINED();
end

-- Local Functions --

function _QuestieComms:BroadcastQuestUpdate(questId) -- broadcast quest update to group or raid
    Questie:Debug(DEBUG_DEVELOP, "[QuestieComms] Questid", questId, tostring(questId));
    if(questId) then
        local partyType = QuestiePlayer:GetGroupType();
        Questie:Debug(DEBUG_DEVELOP, "[QuestieComms] partyType", tostring(partyType));
        if partyType then
            --Do we really need to make this?
            local questPacket = _QuestieComms:createPacket(_QuestieComms.QC_ID_BROADCAST_QUEST_UPDATE);

            local quest = QuestieComms:CreateQuestDataPacket(questId);

            questPacket.data.quest = quest
            questPacket.data.priority = "NORMAL";
            if partyType == "raid" then
                questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLRAID
            else
                questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLGROUP
            end
            questPacket:write();
        end
    end
end

-- Removes the quest from everyones external quest-log
function _QuestieComms:BroadcastQuestRemove(questId) -- broadcast quest update to group or raid
    local partyType = QuestiePlayer:GetGroupType();
    Questie:Debug(DEBUG_DEVELOP, "[QuestieComms] QuestID:", questId, "partyType:", tostring(partyType));
    if partyType then
        --Do we really need to make this?
        local questPacket = _QuestieComms:createPacket(_QuestieComms.QC_ID_BROADCAST_QUEST_REMOVE);

        questPacket.data.id = questId;

        --This is important!
        questPacket.data.priority = "ALERT";
        if partyType == "raid" then
            questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLRAID;
        else
            questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLGROUP;
        end
        questPacket:write();
    end
end

function _QuestieComms:BroadcastQuestLog(eventName) -- broadcast quest update to group or raid
    local partyType = QuestiePlayer:GetGroupType();
    Questie:Debug(DEBUG_DEVELOP, "[QuestieComms] Message", eventName, "partyType:", tostring(partyType));
    if partyType then
        local rawQuestList = {}
        -- Maybe this should be its own function in QuestieQuest...
        local numEntries, numQuests = GetNumQuestLogEntries();
        for index = 1, numEntries do
            local _, _, _, isHeader, _, _, _, questId, _, _, _, _, _, _, _, _, _ = GetQuestLogTitle(index);
            if(not isHeader) then
                -- The id is not needed due to it being used as a key, but send it anyway to keep the same structure.
                local quest = QuestieComms:CreateQuestDataPacket(questId);

                rawQuestList[quest.id] = quest;
            end
        end

        --Do we really need to make this?
        local questPacket = _QuestieComms:createPacket(_QuestieComms.QC_ID_BROADCAST_FULL_QUESTLIST);
        questPacket.data.rawQuestList = rawQuestList;

        if partyType == "raid" then
            questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLRAID;
            questPacket.data.priority = "BULK";
        else
            questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLGROUP;
            questPacket.data.priority = "NORMAL";
        end
        questPacket:write();
    end
end

-- The "Hi" of questie, request others to send their questlog.
function _QuestieComms:RequestQuestLog(eventName) -- broadcast quest update to group or raid
    local partyType = QuestiePlayer:GetGroupType();
    Questie:Debug(DEBUG_DEVELOP, "[QuestieComms] Message", eventName, "partyType:", tostring(partyType));
    if partyType then
        --Do we really need to make this?
        local questPacket = _QuestieComms:createPacket(_QuestieComms.QC_ID_REQUEST_FULL_QUESTLIST);

        if partyType == "raid" then
            questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLRAID;
            questPacket.data.priority = "NORMAL";
        else
            questPacket.data.writeMode = _QuestieComms.QC_WRITE_ALLGROUP;
            questPacket.data.priority = "NORMAL";
        end
        questPacket:write();
    end
end

---@param questId integer @QuestID
---@return QuestPacket
function QuestieComms:CreateQuestDataPacket(questId)
    local questObject = QuestieDB:GetQuest(questId);

    ---@class QuestPacket
    local quest = {};
    quest.id = questId;
    local rawObjectives = QuestieQuest:GetAllLeaderBoardDetails(questId);
    quest.objectives = {}
    if questObject then
        for objectiveIndex, objective in pairs(rawObjectives) do
            quest.objectives[objectiveIndex] = {};
            quest.objectives[objectiveIndex].id = questObject.Objectives[objectiveIndex].Id;--[_QuestieComms.idLookup["id"]] = questObject.Objectives[objectiveIndex].Id;
            quest.objectives[objectiveIndex].typ = string.sub(objective.type, 1, 1);-- Get the first char only.--[_QuestieComms.idLookup["type"]] = string.sub(objective.type, 1, 1);-- Get the first char only.
            quest.objectives[objectiveIndex].fin = objective.finished;--[_QuestieComms.idLookup["finished"]] = objective.finished;
            quest.objectives[objectiveIndex].ful = objective.numFulfilled;--[_QuestieComms.idLookup["fulfilled"]] = objective.numFulfilled;
            quest.objectives[objectiveIndex].req = objective.numRequired;--[_QuestieComms.idLookup["required"]] = objective.numRequired;
        end
    end
    Questie:Debug(DEBUG_SPAM, "[QuestieComms] questPacket made: Objectivetable:", quest.objectives);
    return quest;
end

---@param questPacket QuestPacket @A packet created from the CreateQuestDataPacket function
---@param playerName string @The player said package should be added to.
function QuestieComms:InsertQuestDataPacket(questPacket, playerName)
    --We don't want to insert our own quest data.
    if questPacket and playerName ~= UnitName("player") then
        --Does it contain id and objectives?
        if(questPacket.objectives and questPacket.id) then
            -- Create empty quest.
            if not QuestieComms.remoteQuestLogs[questPacket.id] then
                QuestieComms.remoteQuestLogs[questPacket.id] = {}
            end
            -- Create empty player.
            if not QuestieComms.remoteQuestLogs[questPacket.id][playerName] then
                QuestieComms.remoteQuestLogs[questPacket.id][playerName] = {}
            end
            local objectives = {}
            for objectiveIndex, objectiveData in pairs(questPacket.objectives) do
                --This is to check that all the data we require exist.
                objectives[objectiveIndex] = {};
                objectives[objectiveIndex].index = objectiveIndex;
                objectives[objectiveIndex].id = objectiveData.id--[_QuestieComms.idLookup["id"]];
                objectives[objectiveIndex].type = objectiveData.typ--[_QuestieComms.idLookup["type"]];
                objectives[objectiveIndex].finished = objectiveData.fin--[_QuestieComms.idLookup["finished"]];
                objectives[objectiveIndex].fulfilled = objectiveData.ful--[_QuestieComms.idLookup["fulfilled"]];
                objectives[objectiveIndex].required = objectiveData.req--[_QuestieComms.idLookup["required"]];
            end
            QuestieComms.remoteQuestLogs[questPacket.id][playerName] = objectives;


            --Write to tooltip data
            QuestieComms.data:RegisterTooltip(questPacket.id, playerName, objectives);
        end
    end
end

_QuestieComms.packets = {
    [_QuestieComms.QC_ID_BROADCAST_QUEST_UPDATE] = { --1
        write = function(self);
            Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Sending: QC_ID_BROADCAST_QUEST_UPDATE");
            _QuestieComms:broadcast(self.data);
        end,
        read = function(remoteQuestPacket);
            if(remoteQuestPacket == nil) then
                Questie:Error("[QuestieComms]", "QC_ID_BROADCAST_QUEST_UPDATE", "remoteQuestPacket = nil");
            end
            --These are not strictly needed but helps readability.
            local playerName = remoteQuestPacket.playerName;
            local quest = remoteQuestPacket.quest;

            Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Received: QC_ID_BROADCAST_QUEST_UPDATE", "Player:", playerName);

            QuestieComms:InsertQuestDataPacket(quest, playerName);
        end
    },
    [_QuestieComms.QC_ID_BROADCAST_QUEST_REMOVE] = { --2
      write = function(self);
        Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Sending: QC_ID_BROADCAST_QUEST_REMOVE");
        _QuestieComms:broadcast(self.data);
      end,
      read = function(remoteQuestPacket);
        if(remoteQuestPacket == nil) then
            Questie:Error("[QuestieComms]", "QC_ID_BROADCAST_QUEST_REMOVE", "remoteQuestPacket = nil");
        end
        Questie:Debug(DEBUG_DEVELOP, "[QuestieComms]", "Received: QC_ID_BROADCAST_QUEST_REMOVE");

        local playerName = remoteQuestPacket.playerName;
        local questId = remoteQuestPacket.id;

        if(QuestieComms.remoteQuestLogs[questId] and QuestieComms.remoteQuestLogs[questId][playerName]) then
            Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Removed quest:", questId, "for player:", playerName);
            QuestieComms.remoteQuestLogs[questId][playerName] = nil;
        end
        QuestieComms.data:RemoveQuestFromPlayer(questId, playerName);
      end
    },
    [_QuestieComms.QC_ID_BROADCAST_FULL_QUESTLIST] = { --10
        write = function(self);
            Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Sending: QC_ID_BROADCAST_FULL_QUESTLIST");
            _QuestieComms:broadcast(self.data);
        end,
        read = function(remoteQuestList);
            if(remoteQuestList == nil) then
                Questie:Error("[QuestieComms]", "QC_ID_BROADCAST_FULL_QUESTLIST", "remoteQuestList = nil");
            end
            --These are not strictly needed but helps readability.
            local playerName = remoteQuestList.playerName;
            local questList = remoteQuestList.rawQuestList;

            Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Received: QC_ID_BROADCAST_FULL_QUESTLIST", "Player:", playerName, questList);

            --Don't save our own quests.
            if questList then
                for questId, questData in pairs(questList) do
                    QuestieComms:InsertQuestDataPacket(questData, playerName);
                end
            end
        end
    },
    [_QuestieComms.QC_ID_REQUEST_FULL_QUESTLIST] = { --11
        write = function(self);
            Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Sending: QC_ID_REQUEST_FULL_QUESTLIST");
            _QuestieComms:broadcast(self.data);
        end,
        read = function(self);
            Questie:Debug(DEBUG_INFO, "[QuestieComms]", "Received: QC_ID_REQUEST_FULL_QUESTLIST");
            Questie:SendMessage("QC_ID_BROADCAST_FULL_QUESTLIST");
        end
    },
}

-- Renamed Write function
function _QuestieComms:broadcast(packet)
    -- If the priority is not set, it must not be very important
    if(not packet.priority) then
      packet.priority = "BULK";
    end
    
    local compressedData = QuestieSerializer:Serialize(packet);--QuestieCompress:Compress(packet);
    if packet.writeMode == _QuestieComms.QC_WRITE_WHISPER then
        Questie:Debug(DEBUG_DEVELOP,"send(|cFFFF2222" ..string.len(compressedData) .. "|r)");
        Questie:SendCommMessage(_QuestieComms.prefix, compressedData, packet.writeMode, packet.target, packet.priority);
    elseif packet.writeMode == _QuestieComms.QC_WRITE_CHANNEL then
        Questie:Debug(DEBUG_DEVELOP,"send(|cFFFF2222" ..string.len(compressedData) .. "|r)");
        -- Always do channel messages as BULK priority
        Questie:SendCommMessage(_QuestieComms.prefix, compressedData, packet.writeMode, GetChannelName("questiecom"), "BULK");
        --OLD: C_ChatInfo.SendAddonMessage("questie", compressedData, "CHANNEL", GetChannelName("questiecom"));
    else
        Questie:Debug(DEBUG_DEVELOP, "send(|cFFFF2222" ..string.len(compressedData) .. "|r)");
        Questie:SendCommMessage(_QuestieComms.prefix, compressedData, packet.writeMode, nil, packet.priority);
        --OLD: C_ChatInfo.SendAddonMessage("questie", compressedData, packet.writeMode);
    end
end

function _QuestieComms:OnCommReceived(message, distribution, sender)
    Questie:Debug(DEBUG_DEVELOP, "|cFF22FF22", "sender:", "|r", sender, "distribution:", distribution, "Packet length:",string.len(message));
    if message and sender then
        local decompressedData = QuestieSerializer:Deserialize(message);--QuestieCompress:Decompress(message);
        
        --Check if the message version is the same base value
        if(decompressedData and decompressedData.msgVer and floor(decompressedData.msgVer) == floor(commMessageVersion)) then
            if(decompressedData and decompressedData.msgId and _QuestieComms.packets[decompressedData.msgId]) then

                --If a new version exist, tell them!
                if(suggestUpdate) then
                    local major, minor, patch = strsplit(".", decompressedData.ver);
                    local majorOwn, minorOwn, patchOwn = QuestieLib:GetAddonVersionInfo();
                    if((majorOwn < tonumber(major) or minorOwn < tonumber(minor)) and not UnitAffectingCombat("player")) then
                        suggestUpdate = false;
                        if(majorOwn < tonumber(major)) then
                            Questie:Print("A Major patch for Questie exist! Please update as soon as possible!");
                        elseif(majorOwn == tonumber(major) and minorOwn < tonumber(minor)) then
                            Questie:Print("You have an outdated version of Questie! Please consider updating!");
                        end
                    end
                end

                decompressedData.playerName = sender;
                Questie:Debug(DEBUG_DEVELOP, "Executing message ID: ", decompressedData.msgId, "From: ", sender, "MessageVersion:", decompressedData.msgVer);

                _QuestieComms.packets[decompressedData.msgId].read(decompressedData);
            else
                Questie:Debug(DEBUG_INFO, "[QuestieComms]", decompressedData, decompressedData.msgId, _QuestieComms.packets[decompressedData.msgId]);
                Questie:Error("Error reading QuestieComm message (If it persist try updating) Player:", sender, "PacketLength:", string.len(message));
            end
        elseif(decompressedData and not warnedUpdate and decompressedData.msgVer) then
            -- We want to know who actually is the one with the mismatched version!
            if(floor(commMessageVersion) < floor(decompressedData.msgVer)) then
                Questie:Error("You have an incompatible QuestieComms message! Please update!", "  Yours: v", commMessageVersion, sender..": v", decompressedData.msgVer);
            elseif(floor(commMessageVersion) > floor(decompressedData.msgVer)) then
                Questie:Print("|cFFFF0000WARNING!|r", sender, "has an incompatible Questie version, QuestieComms won't work!", " Yours:", commMessageVersion, sender..":", decompressedData.msgVer);
            end
            warnedUpdate = true;
        end
    end
end

-- Copied: Is this really needed? Can't we just optimize away this?
function _QuestieComms:createPacket(messageId)
    -- Duplicate the object.
    local pkt = {};
    for k,v in pairs(_QuestieComms.packets[messageId]) do
        pkt[k] = v
    end
    pkt.data = {}
    -- Set messageId
    local major, minor, patch = QuestieLib:GetAddonVersionInfo();
    pkt.data.ver = major.."."..minor.."."..patch;
    pkt.data.msgVer = commMessageVersion;
    pkt.data.msgId = messageId
    -- Some messages initialize
    if pkt.init then
        pkt:init();
    end
    return pkt
end

function QuestieComms:ResetAll()
    QuestieComms.data:ResetAll();
    QuestieComms.remoteQuestLogs = {};
end

