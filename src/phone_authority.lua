local WorkPhone = require("src.work_phone")

local Phone = {}

function Phone.resource(options)
    local state = assert(options.state)
    local commands = {}
    for action, operation in pairs({ phone_answer = WorkPhone.answer,
        phone_respond = WorkPhone.respond, phone_dismiss = WorkPhone.dismiss }) do
        commands[action] = {
            normalize = function(args)
                if type(args) ~= "table" or type(args.callId) ~= "string"
                    or not args.callId:match("^CALL%-%d+$") or #args.callId > 64 then
                    return nil, "invalid_call", "Choose the current phone call."
                end
                for key in pairs(args) do if key ~= "callId" then return nil, "invalid_arguments" end end
                return { callId = args.callId }
            end,
            perform = function(_, player, args)
                local allowed, code, message = options.world.validateNetworkWorkshopAccess(player, state, "work_phone")
                if not allowed then return false, code, message, {} end
                local call = WorkPhone.ensure(state).incoming
                if not call or call.id ~= args.callId then
                    return false, "call_changed", "That call has ended. Check the current phone line.", {}
                end
                if action == "phone_answer" and call.answered then
                    return false, "already_answered", "This call is already connected.", {}
                end
                local ok, result = operation(state)
                if ok then options.save() end
                return ok == true, ok and "completed" or "phone_blocked",
                    type(result) == "string" and result or (ok and "Phone line connected." or "Phone action unavailable."), {}
            end,
        }
    end
    return {
        canAcquire = function(player)
            return options.world.validateNetworkWorkshopAccess(player, state, "work_phone")
        end,
        onAcquire = function() return true, "acquired", "Work phone connected.", {} end,
        commands = commands,
    }
end

return Phone
