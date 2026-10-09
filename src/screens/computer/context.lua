-- Office dependencies, layout, and per-console state.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.dependencies = Runtime.dependencies or {}
    Runtime.Config = require("src.config")
    Runtime.BusinessCalendar = require("src.business_calendar")
    Runtime.JobService = require("src.job_service")
    Runtime.MachineFleet = require("src.machine_fleet")
    Runtime.Procurement = require("src.procurement")
    Runtime.BackButton = require("src.screens.back_button")
    Runtime.StatusLabels = require("src.status_labels")
    Runtime.Ui = require("src.screens.ui")
    Runtime.utf8 = require("utf8")
    Runtime.Reputation = require("src.reputation")
    Runtime.Upgrades = require("src.warehouse_upgrades")
    Runtime.BreakroomGames = require("src.breakroom_games")
    Runtime.Credit = require("src.credit")
    Runtime.OfficeIntent = require("src.office_intent")
    Runtime.Hiring = require("src.screens.hiring_screen")
    Runtime.ScheduleScreen = require("src.screens.schedule_screen")
    Runtime.Employees = require("src.employees")
    Runtime.Payroll = require("src.payroll")
    Runtime.warehouseRequestPrefix=Runtime.dependencies.warehouseRequestPrefix

    function Runtime.nextFinanceRequestId(sequence)
        Runtime.warehouseRequestPrefix=tostring(Runtime.warehouseRequestPrefix
            or ("FIN-"..os.time().."-"..math.random(1,99999999))):gsub("[^%w_.%-]","-"):sub(1,36)
        return string.format("FIN-%s-%d-%d",Runtime.warehouseRequestPrefix,os.time(),sequence)
    end

    Runtime.ComputerScreen = {
        tab = "active",
        emailFolder = "inbox",
        selectedJobId = nil,
        selectedEmailId = nil,
        emailPage = 1,
        emailSelectionRequired = false,
        pages = { active = 1, completed = 1, deliveries = 1 },
        quoteText = "",
        quoteFocused = false,
        quoteReplaceOnType = true,
        promoJobId = nil,
        promoText = "",
        promoFocused = false,
        calendarYear = nil,
        calendarMonth = nil,
        calendarSelectedDay = nil,
        calendarScroll = 0,
        retailPage = 1,
        wwwSite = 1,
        cart = {},
        cartOpen = false,
        cartPage = 1,
        machinePage = 1,
        wwwSiteChangedAt = 0,
        tabDropdownOpen = false,
        warehouseConfirmation = nil,
        warehousePending = false,
        warehouseMessage = nil,
        warehouseRequestNumber = 0,
        warehouseGamesPage = false,
        creditConfirmation = nil,
        creditRequestNumber = 0,
        creditChannel = "online",
        hiring = Runtime.Hiring.new(),
        schedule = Runtime.ScheduleScreen.new(),
    }

    Runtime.PANEL = { x = 52, y = 34, width = 856, height = 610 }
    Runtime.CLOSE = { x = 756, y = 48, width = 132, height = 40 }
    Runtime.TABS = {
        { id = "active", label = "ACTIVE JOBS", url = "www.thecritternet.com/job-desk/active" },
        { id = "completed", label = "COMPLETED JOBS", url = "www.thecritternet.com/job-desk/completed" },
        { id = "deliveries", label = "DELIVERIES", url = "www.thecritternet.com/job-desk/deliveries" },
        { id = "estimating", label = "ESTIMATING", url = "www.thecritternet.com/job-desk/estimating" },
        { id = "calendar", label = "CALENDAR", url = "www.thecritternet.com/job-desk/calendar" },
        { id = "clock", label = "SHOP CLOCK", url = "www.thecritternet.com/shop/clock" },
        { id = "inventory", label = "INVENTORY", url = "www.thecritternet.com/job-desk/inventory" },
        { id = "www", label = "CRITTERNET WWW", url = "www.thecritternet.com" },
        { id = "email", label = "EMAIL", url = "www.thecritternet.com/job-desk/email" },
        { id = "hiring", label = "HIRING", url = "www.thecritternet.com/shop/hiring" },
        { id = "schedule", label = "SCHEDULE", url = "www.thecritternet.com/shop/schedule" },
        { id = "bills", label = "BILLS", url = "www.thecritternet.com/job-desk/bills" },
        { id = "credit", label = "CREDIT", url = "www.thecritternet.com/job-desk/credit" },
        { id = "warehouse", label = "WAREHOUSE", url = "www.thecritternet.com/warehouse" },
    }
    Runtime.TAB_ADDRESS = { x = 170, y = 136, width = 478, height = 40 }
    Runtime.TAB_DROPDOWN_ARROW = { x = 648, y = 136, width = 40, height = 40 }
    Runtime.TAB_DROPDOWN = { x = 170, y = 179, width = 518, rowHeight = 33 }
    Runtime.LIST = { x = 82, y = 190, width = 310, height = 370 }
    Runtime.DETAIL = { x = 412, y = 190, width = 440, height = 444 }
    Runtime.PREVIOUS = { x = 82, y = 570, width = 86, height = 30 }
    Runtime.NEXT = { x = 306, y = 570, width = 86, height = 30 }
    Runtime.COMPLETE = { x = 598, y = 598, width = 228, height = 36 }
    Runtime.MONITOR = { x = 16, y = 8, width = 928, height = 660 }
    Runtime.WWW_SITE = { x = 92, y = 238, width = 140, height = 42, gap = 8 }
    Runtime.WWW_PRODUCT = { x = 92, y = 296, width = 748, rowHeight = 52, gap = 6 }
    Runtime.WWW_SITES = {
        { name = "PAPER DEPOT", short = "PAPER", url = "www.thecritternet.com/paper-depot", categoryIndex = 1 },
        { name = "PRESSROOM SUPPLY", short = "PRESS", url = "www.thecritternet.com/pressroom", categoryIndex = 2 },
        { name = "CARTON & WRAP", short = "PACKING", url = "www.thecritternet.com/cartons", categoryIndex = 3 },
        { name = "WRENCHWORKS", short = "TOOLS", url = "www.thecritternet.com/tools", categoryIndex = 4 },
        { name = "MACHINE MARKET", short = "MACHINES", url = "www.thecritternet.com/machines", kind = "machines" },
    }
    Runtime.CART_BUTTON = { x = 714, y = 194, width = 126, height = 36 }
    Runtime.CART_BACK = { x = 102, y = 548, width = 126, height = 40 }
    Runtime.CART_CLEAR = { x = 244, y = 548, width = 126, height = 40 }
    Runtime.CART_CHECKOUT = { x = 630, y = 548, width = 190, height = 40 }
    Runtime.CART_PREVIOUS = { x = 400, y = 552, width = 42, height = 32 }
    Runtime.CART_NEXT = { x = 514, y = 552, width = 42, height = 32 }
    Runtime.CART_PAGE_SIZE = 7
    Runtime.PAY_BILLS = { x = 612, y = 522, width = 196, height = 46 }
    Runtime.EMAIL_QUOTE_INPUT = { x = 434, y = 470, width = 190, height = 40 }
    Runtime.EMAIL_ACCEPT = { x = 640, y = 470, width = 186, height = 40 }
    Runtime.EMAIL_DECLINE = { x = 434, y = 526, width = 186, height = 44 }
    Runtime.EMAIL_DELETE = { x = 640, y = 526, width = 186, height = 44 }
    Runtime.EMAIL_FOLDER_INBOX = { x = 94, y = 218, width = 128, height = 28 }
    Runtime.EMAIL_FOLDER_ARCHIVE = { x = 230, y = 218, width = 144, height = 28 }
    Runtime.EMAIL_PREVIOUS = { x = 94, y = 562, width = 82, height = 28 }
    Runtime.EMAIL_NEXT = { x = 292, y = 562, width = 82, height = 28 }
    Runtime.EMAIL_PAGE_SIZE = 6
    Runtime.PROMO = { x = 640, y = 526, width = 186, height = 44 }
    Runtime.JOB_PROMO = { x = 640, y = 590, width = 186, height = 44 }
    Runtime.PROMO_INPUT = { x = 434, y = 338, width = 392, height = 122 }
    Runtime.CAL_PREVIOUS = { x = 96, y = 202, width = 42, height = 30 }
    Runtime.CAL_NEXT = { x = 542, y = 202, width = 42, height = 30 }
    Runtime.CAL_GRID = { x = 94, y = 272, cellWidth = 70, cellHeight = 54 }
    Runtime.CAL_EVENT_LIST = { x = 624, y = 240, width = 216, rowHeight = 34, visibleRows = 9 }
    Runtime.CAL_SCROLL_UP = { x = 624, y = 558, width = 102, height = 28 }
    Runtime.CAL_SCROLL_DOWN = { x = 738, y = 558, width = 102, height = 28 }
    Runtime.MACHINE_OFFER = { x = 92, y = 296, width = 354, height = 82, gap = 10 }
    Runtime.OWNED_MACHINE = { x = 486, y = 296, width = 354, height = 64, gap = 8 }
    Runtime.ComputerScreen.machinePageSize = 4
    Runtime.ComputerScreen.machinePreviousRect = { x = 490, y = 588, width = 78, height = 28 }
    Runtime.ComputerScreen.machineNextRect = { x = 760, y = 588, width = 78, height = 28 }
    Runtime.ROW_HEIGHT = 46
    Runtime.JOBS_PER_PAGE = 7

    Runtime.contains, Runtime.commaNumber, Runtime.money = Runtime.Ui.contains, Runtime.Ui.commaNumber, Runtime.Ui.money

    Runtime.WAREHOUSE_BAYS = { "front_left", "front_right" }
    Runtime.WAREHOUSE_OPTIONS = { "floor", "storage", "breakroom" }
    Runtime.WAREHOUSE_FORKLIFT = {x=670,y=490,width=164,height=40}
    Runtime.WAREHOUSE_CONFIRM = {x=508,y=514,width=228,height=40}
    Runtime.WAREHOUSE_CANCEL = {x=216,y=514,width=180,height=40}
    Runtime.WAREHOUSE_ACK = {x=206,y=430,width=542,height=48}
    Runtime.CREDIT_MACHINE = { x = 98, y = 306, width = 350, height = 76, gap = 8 }
    Runtime.CREDIT_MACHINE_ACTION = { x = 354, width = 88, height = 32 }
    Runtime.CREDIT_CHANNEL_ONLINE = { x = 262, y = 279, width = 78, height = 22 }
    Runtime.CREDIT_CHANNEL_DEALER = { x = 344, y = 279, width = 88, height = 22 }
    Runtime.CREDIT_LOAN = { x = 462, y = 300, width = 366, height = 76, gap = 8 }
    Runtime.CREDIT_LOAN_ACTION = { x = 712, width = 104, height = 29 }
    Runtime.CREDIT_SIGN = { x = 492, y = 472, width = 220, height = 44 }
    Runtime.CREDIT_CANCEL = { x = 248, y = 472, width = 200, height = 44 }
    Runtime.CREDIT_CONFIRM_PANEL = { x = 148, y = 302, width = 640, height = 232 }
end

return Component
