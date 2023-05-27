local name, addon = ...;

Mixin(addon, CallbackRegistryMixin)
addon:GenerateCallbackEvents({
    "Database_OnInitialised",
    "Dailies_OnQuestAdded",
    "Dailies_OnQuestTurnedIn",
})
CallbackRegistryMixin.OnLoad(addon);

TheBoringDad_DailiesMixin = {
    launcher = {
        name = "Dailies",
        icon = "QuestDaily",
    },
    selectedCharacter = "",
};

function TheBoringDad_DailiesMixin:OnLoad()
    self:RegisterEvent("QUEST_ACCEPTED")
    self:RegisterEvent("QUEST_TURNED_IN")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    addon:RegisterCallback("Database_OnInitialised", self.Database_OnInitialised, self)
    addon:RegisterCallback("Dailies_OnQuestAdded", self.Dailies_OnQuestAdded, self)

end

function TheBoringDad_DailiesMixin:UpdateLayout()
    local x, y = self:GetSize()

    self.charactersListview:SetWidth(x * 0.25)
end

function TheBoringDad_DailiesMixin:Database_OnInitialised()

    local name, realm = UnitFullName("player")
    if not realm then
        realm = GetNormalizedRealmName()
    end
    self.currentCharacter = string.format("%s-%s", name, realm)

    if not self.db.characters[self.currentCharacter] then
        self.db.characters[self.currentCharacter] = {};
    end

    self:LoadCharacters()
    self:LoadDailiesquestsListview(self.currentCharacter)

    TheBoringDad:RegisterModule(self)
    self:UpdateLayout()

end

function TheBoringDad_DailiesMixin:OnEvent(event, ...)
    if self[event] then
        self[event](self, ...)
    end
end

function TheBoringDad_DailiesMixin:PLAYER_ENTERING_WORLD(initial, reload)
    
    if not TBD_DB_DAILIES then
        TBD_DB_DAILIES = {
            quests = {},
            characters = {}
        };
    end

    self.db = TBD_DB_DAILIES;

    addon:TriggerEvent("Database_OnInitialised")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function TheBoringDad_DailiesMixin:QUEST_TURNED_IN(questID, xpReward, moneyReward)

    local now = time()
    local resetTime = now + C_DateAndTime.GetSecondsUntilDailyReset()

    local info  = {
        turnedIn = now,
        resets = resetTime,
        gold = moneyReward,
        xp = xpReward,
    }
    self.db.characters[self.currentCharacter][questID] = info;

    if self.selectedCharacter == self.currentCharacter then
        addon:TriggerEvent("Dailies_OnQuestTurnedIn", questID, info)
    end

end

function TheBoringDad_DailiesMixin:QUEST_ACCEPTED(_questLogIndex, _questId)

    local header;
    for i = 1, GetNumQuestLogEntries() do

        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questId = GetQuestLogTitle(i)
        if isHeader then
            header = title;
        end
        if frequency == 2 then
            local questDescription, questObjectives = GetQuestLogQuestText(i)
            local questLink = GetQuestLink(questId)
            self.db.quests[questId] = {
                link = questLink,
                title = title,
                header = header,
                questId = questId,
                description = questDescription,
                objectives = questObjectives,
                level = level,
            }
            addon:TriggerEvent("Dailies_OnQuestAdded")
        end
    end
end

function TheBoringDad_DailiesMixin:LoadCharacters()
    if self.db and self.db.characters then
        for nameRealm, _ in pairs(self.db.characters) do
            self.charactersListview.DataProvider:Insert({
                label = nameRealm,
                onMouseDown = function()
                    self.selectedCharacter = nameRealm;
                    self:LoadDailiesquestsListview(nameRealm)
                end,
            })
        end
    end
end

function TheBoringDad_DailiesMixin:Dailies_OnQuestAdded()
    self:LoadDailiesquestsListview(self.currentCharacter)
end


function TheBoringDad_DailiesMixin:LoadDailiesquestsListview(character)
    local t = {}
    local characterLevel = UnitLevel("player")
    for questId, info in pairs(self.db.quests) do
        if self.db.characters[character] and self.db.characters[character][questId] then
            table.insert(t, {
                info = info,
                turnIn = self.db.characters[character][questId],
            })
        else
            table.insert(t, {
                info = info,
                turnIn = false,
            })
        end
    end
    table.sort(t, function(a, b)
        -- if a.header == b.header then
        --     return a.level > b.level;
        -- else
        --     return a.header < b.header;
        -- end
        return a.info.header < b.info.header;
    end)


    self.questsListview.DataProvider:Flush()

    local headers = {}
    for k, quest in ipairs(t) do
        if not headers[quest.info.header] then
            self.questsListview.DataProvider:Insert({
                isHeader = true,
                header = quest.info.header,
            })
            headers[quest.info.header] = true
        end
        self.questsListview.DataProvider:Insert(quest)
    end

end


function TheBoringDad_DailiesMixin:CheckQuestsCompleted()
    for questId, info in pairs(self.db.quests) do
        local isComplete = C_QuestLog.IsQuestFlaggedCompleted(questId)
    end
end





TheBoringDads_DailiesListviewItemMixin = {}
function TheBoringDads_DailiesListviewItemMixin:OnLoad()
    addon:RegisterCallback("Dailies_OnQuestTurnedIn", self.Dailies_OnQuestTurnedIn, self)

    self.completed:EnableMouse(false)
end

function TheBoringDads_DailiesListviewItemMixin:SetDataBinding(binding, height)

    self.completed.label:SetText("")
    self.info:Hide()
    self.completed:SetChecked(false)

    self:SetHeight(height)

    self.daily = binding;

    self:SetScript("OnLeave", function()
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    end)

    --if this is a header line just set text
    if binding.isHeader then
        self:EnableMouse(false)
        self.completed:Hide()
        self.header:Show()
        self.header:SetText(binding.header)
        self.background:Show()

    --if this is a quest do fancy stuff
    else
        self:EnableMouse(true)
        self.completed:Show()
        self.completed.label:SetText(string.format("[%s]",binding.info.title))
        self.header:Hide()
        self.background:Hide()

        if type(binding.turnIn) == "table" then
            if time() < binding.turnIn.resets then
                self.info:SetText(string.format("[%s] %s %s XP", date('%Y-%m-%d %H:%M:%S', binding.turnIn.turnedIn), GetCoinTextureString(binding.turnIn.gold), (binding.turnIn.xp or 0)))
                self.info:Show()
                self.completed:SetChecked(true)
            end
        end
    end

end

function TheBoringDads_DailiesListviewItemMixin:Dailies_OnQuestTurnedIn(questId, turnIn)

    if self.daily and self.daily.info and (self.daily.info.questId == questId) and (time() < turnIn.resets) then
        self.completed:SetChecked(true)
        self.info:SetText(string.format("[%s] %s %s XP", date('%Y-%m-%d %H:%M:%S', turnIn.turnedIn), GetCoinTextureString(turnIn.gold), (turnIn.xp or 0)))
        self.info:Show()
    end
end

function TheBoringDads_DailiesListviewItemMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(self.daily.info.link)
    GameTooltip:Show()
end

function TheBoringDads_DailiesListviewItemMixin:ResetDataBinding()

end