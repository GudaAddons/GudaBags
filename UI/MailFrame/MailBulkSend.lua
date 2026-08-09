-- GudaBags Bulk Mail Send
-- Shift+Right-Click a bag item at a mailbox to attach every copy of it across the
-- bags, auto-sending whenever the attachment limit fills.
--
-- The click is intercepted in UI/ItemButton.lua's PreClick (same mechanism as the
-- warband deposit intercept) and lands here via MailBulkSend:Start().
--
-- Blizzard blanks the Send Mail form after every successful send, so the batch puts
-- the recipient back into the To field itself (see RestoreRecipient).

local addonName, ns = ...

local MailBulkSend = {}
ns:RegisterModule("MailBulkSend", MailBulkSend)

local Constants = ns.Constants
local L = ns.L
local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")
local Utils = ns:GetModule("Utils")

-- Batch state. Only one batch can run at a time (guarded by isRunning).
local isRunning = false
local queue = {}          -- pending stacks: { bagID, slot, count }
local pendingRound = {}   -- stacks attached this round, awaiting verification
local batchItemID = nil
local batchItemName = ""
local batchRecipient = ""
local attachedCount = 0   -- items (not stacks) successfully attached
local mailsSent = 0
local skippedStacks = 0   -- stacks that refused to attach (soulbound etc.)

-- Delay between attaching and reading back the attachment slots. Attaching is a
-- client-side operation but is not guaranteed to be visible to GetSendMailItem on
-- the very next line, so every round verifies after a short settle.
local SETTLE_DELAY = 0.2

local function MaxAttachments()
    return ATTACHMENTS_MAX_SEND or 12
end

-- Blizzard charges a flat postage per mail. GetSendMailPrice is not present on
-- every supported client, so fall back to the classic 30 copper.
local function Postage()
    if GetSendMailPrice then
        return GetSendMailPrice() or 30
    end
    return 30
end

local function CountAttachments()
    local count = 0
    for i = 1, MaxAttachments() do
        if GetSendMailItem(i) then
            count = count + 1
        end
    end
    return count
end

local function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local function GetRecipient()
    return Trim(_G.SendMailNameEditBox and _G.SendMailNameEditBox:GetText())
end

local function GetSubject()
    return Trim(_G.SendMailSubjectEditBox and _G.SendMailSubjectEditBox:GetText())
end

local function GetBody()
    return _G.SendMailBodyEditBox and _G.SendMailBodyEditBox:GetText() or ""
end

-- Blizzard's SendMailFrame_Reset() blanks the To box on MAIL_SEND_SUCCESS. The batch keeps
-- sending correctly (batchRecipient is cached), but an empty field means the next
-- Shift+Right-Click would fall into the attach-only path, so put the name back.
local function RestoreRecipient()
    if batchRecipient == "" then return end
    local box = _G.SendMailNameEditBox
    if not box then return end
    if box:GetText() ~= batchRecipient then
        box:SetText(batchRecipient)
    end
end

-------------------------------------------------
-- Preconditions
-------------------------------------------------

-- Cheap predicate used by ItemButton's PreClick: it must be false whenever the
-- shortcut is not applicable, so a stray Shift+Right-Click never disturbs the
-- secure button's IDs.
function MailBulkSend:CanStart()
    if not Database:GetSetting("mailBulkAttach") then return false end
    if isRunning then return false end
    if InCombatLockdown() then return false end

    local MailScanner = ns:GetModule("MailScanner")
    if not (MailScanner and MailScanner:IsMailboxOpen()) then return false end

    -- Attachments only exist on the Send Mail tab.
    if not (_G.SendMailFrame and _G.SendMailFrame:IsShown()) then return false end

    return true
end

-- Re-checked at every step: the mailbox can close (or combat can start) mid-batch.
-- Deliberately does not rely on MAIL_CLOSED, which UI/BagFrame.lua documents as
-- unreliable on Classic Anniversary.
local function CanContinue()
    if InCombatLockdown() then return false end
    local MailScanner = ns:GetModule("MailScanner")
    if not (MailScanner and MailScanner:IsMailboxOpen()) then return false end
    if not (_G.SendMailFrame and _G.SendMailFrame:IsShown()) then return false end
    return true
end

-------------------------------------------------
-- Bag scan
-------------------------------------------------

-- Collect every mailable stack of itemID across the player's bags. Mirrors the
-- exclusion rules used by AutoVendorJunk (UI/BagFrame.lua): the addon's own item
-- locks and equipment-set protection are both honoured.
local function CollectStacks(itemID)
    local stacks = {}
    local EquipSets = ns:GetModule("EquipmentSets")
    local autoLockSets = Database:GetSetting("autoLockSetItems")

    -- BAG_IDS, not PLAYER_BAG_MIN..PLAYER_BAG_MAX: that range stops at 4 and so skips
    -- the Retail reagent bag (5), which lives in its own Constants.REAGENT_BAG. The
    -- PreClick intercept has no such limit, so a reagent-bag item used to have its
    -- native attach suppressed and then find zero stacks here — a silent no-op.
    for _, bagID in ipairs(Constants.BAG_IDS) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            -- isBound is absent on older clients; when present it lets us skip
            -- soulbound stacks up front instead of attempting a doomed attach.
            if info and info.itemID == itemID
                and not info.isLocked
                and not info.isBound
                and not Database:IsItemLocked(info.itemID)
                and not (autoLockSets and EquipSets and EquipSets:IsInSet(info.itemID)) then
                stacks[#stacks + 1] = {
                    bagID = bagID,
                    slot = slot,
                    count = info.stackCount or 1,
                }
            end
        end
    end

    return stacks
end

-------------------------------------------------
-- Batch execution
-------------------------------------------------

local Step  -- forward declaration

local function Finish(messageKey, ...)
    isRunning = false
    queue = {}
    pendingRound = {}
    Events:UnregisterAll("MailBulkSend")

    if messageKey then
        ns:Print(string.format(L[messageKey], ...))
    end
    if skippedStacks > 0 then
        ns:Print(string.format(L["MAIL_BULK_UNMAILABLE"], skippedStacks))
    end
end

local function SendCurrentMail()
    local subject = GetSubject()
    if subject == "" then
        subject = batchItemName
    end

    -- MailScanner hooks SendMail, so its predicted-mail bookkeeping for known alts
    -- updates from this call automatically.
    SendMail(batchRecipient, subject, GetBody())
end

-- Verify what actually landed in the attachment slots, then either send or stop.
local function AfterAttach()
    if not CanContinue() then
        Finish("MAIL_BULK_STOPPED", mailsSent)
        return
    end

    -- A stack that is still sitting in its bag slot never attached (soulbound or
    -- otherwise unmailable). Counting it here keeps the summary honest instead of
    -- assuming every UseContainerItem call succeeded.
    for _, entry in ipairs(pendingRound) do
        local info = C_Container.GetContainerItemInfo(entry.bagID, entry.slot)
        if info and info.itemID == batchItemID then
            skippedStacks = skippedStacks + 1
        else
            attachedCount = attachedCount + entry.count
        end
    end
    pendingRound = {}

    local attached = CountAttachments()

    if attached == 0 then
        -- Nothing attached this round. Every popped stack was unmailable; if the
        -- queue is also empty there is nothing left to do.
        if #queue == 0 then
            Finish("MAIL_BULK_STOPPED", mailsSent)
        else
            Step()
        end
        return
    end

    -- No recipient: leave the composed mail for the user rather than guessing.
    -- batchRecipient is deliberately NOT re-read here — the confirmation popup named
    -- a specific recipient, and editing the To field mid-batch must not silently
    -- redirect the remaining mails somewhere else.
    if batchRecipient == "" then
        Finish("MAIL_BULK_ATTACHED", attachedCount, batchItemName)
        return
    end

    SendCurrentMail()
    -- MAIL_SEND_SUCCESS drives the next round (or the finish).
end

Step = function()
    if not CanContinue() then
        Finish("MAIL_BULK_STOPPED", mailsSent)
        return
    end

    local free = MaxAttachments() - CountAttachments()
    pendingRound = {}

    while free > 0 and #queue > 0 do
        local entry = table.remove(queue, 1)

        -- Verify the slot still holds what we planned to send before acting on it.
        local info = C_Container.GetContainerItemInfo(entry.bagID, entry.slot)
        if info and info.itemID == batchItemID and not info.isLocked then
            C_Container.UseContainerItem(entry.bagID, entry.slot)
            pendingRound[#pendingRound + 1] = entry
            free = free - 1
        else
            skippedStacks = skippedStacks + 1
        end
    end

    -- The queue strictly shrinks every round, so this always terminates.
    C_Timer.After(SETTLE_DELAY, AfterAttach)
end

local function OnSendSuccess()
    mailsSent = mailsSent + 1

    -- Deferred by a frame: Blizzard's reset runs during this same event dispatch, and frame
    -- handler order is not guaranteed, so restoring inline could be overwritten. Done before
    -- the queue check so the final mail of the batch is covered too.
    C_Timer.After(0, RestoreRecipient)

    if #queue == 0 then
        Finish("MAIL_BULK_SENT", attachedCount, batchItemName, batchRecipient, mailsSent)
        return
    end

    -- Give the server a moment to clear the send frame before refilling it.
    C_Timer.After(SETTLE_DELAY, Step)
end

local function OnSendFailed()
    Finish("MAIL_BULK_STOPPED", mailsSent)
end

local function BeginBatch()
    isRunning = true
    Events:Register("MAIL_SEND_SUCCESS", OnSendSuccess, "MailBulkSend")
    Events:Register("MAIL_FAILED", OnSendFailed, "MailBulkSend")
    Step()
end

-------------------------------------------------
-- Confirmation popup
-------------------------------------------------

StaticPopupDialogs["GUDABAGS_MAIL_BULK"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        BeginBatch()
    end,
    OnCancel = function()
        queue = {}
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------
-- Entry point
-------------------------------------------------

function MailBulkSend:Start(itemID, itemLink)
    if not itemID then return end

    if isRunning then
        ns:Print(L["MAIL_BULK_BUSY"])
        return
    end
    if not self:CanStart() then return end

    -- Auto-sending a COD mail would bill the recipient; make the user clear it.
    if (GetSendMailCOD() or 0) > 0 then
        ns:Print(L["MAIL_BULK_COD"])
        return
    end

    local stacks = CollectStacks(itemID)
    if #stacks == 0 then return end

    local totalItems = 0
    for _, entry in ipairs(stacks) do
        totalItems = totalItems + entry.count
    end

    local recipient = GetRecipient()
    local mailCount = math.ceil(#stacks / MaxAttachments())
    local cost = mailCount * Postage()

    -- Postage is only charged for mails we actually send.
    if recipient ~= "" and GetMoney() < cost then
        ns:Print(string.format(L["MAIL_BULK_NO_FUNDS"], Utils:FormatMoneyFull(cost)))
        return
    end

    local name = itemLink or (GetItemInfo(itemID)) or tostring(itemID)

    -- Reset batch state before the popup so a cancel leaves nothing behind.
    queue = stacks
    batchItemID = itemID
    batchItemName = name
    batchRecipient = recipient
    attachedCount = 0
    mailsSent = 0
    skippedStacks = 0

    if recipient == "" then
        -- Attach-only: no send, no cost, nothing irreversible — skip the popup.
        BeginBatch()
        return
    end

    StaticPopup_Show("GUDABAGS_MAIL_BULK", string.format(
        L["MAIL_BULK_CONFIRM"],
        name,
        totalItems,
        recipient,
        mailCount,
        Utils:FormatMoneyFull(cost)
    ))
end

return MailBulkSend
