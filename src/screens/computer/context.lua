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
    Runtime.JobFeedback = require("src.job_feedback")
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
        deliveryQuoteText = "",
        deliveryQuoteFocused = false,
        deliveryQuoteReplaceOnType = true,
        includeDeliveryQuote = false,
        promoJobId = nil,
        promoText = "",
        promoFocused = false,
        calendarYear = nil,
        calendarMonth = nil,
        calendarSelectedDay = nil,
        calendarDayOpen = false,
        calendarDayScroll = 0,
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
        vehicleConfirmation = nil,
        vehiclePending = false,
        vehicleMessage = nil,
        vehicleRequestNumber = 0,
        warehouseGamesPage = false,
        warehouseStagingPage = false,
        warehouseSelectedStagingAreaId = "cutter-output",
        warehouseSelectedStagingRoomId = "warehouse",
        creditConfirmation = nil,
        creditRequestNumber = 0,
        creditChannel = "online",
        hiring = Runtime.Hiring.new(),
        financialSection = "overview",
        financialHiring = Runtime.Hiring.new(),
        schedule = Runtime.ScheduleScreen.new(),
    }
    function Runtime.ComputerScreen.configureRadio(options)
        Runtime.dependencies.isNetworkClient=options and options.isNetworkClient
    end
    function Runtime.ComputerScreen.configureTimeFormat(provider)
        Runtime.dependencies.twelveHourTime=provider
    end
    function Runtime.twelveHourTime()
        local setting=Runtime.dependencies.twelveHourTime
        if type(setting)=='function' then setting=setting() end
        return setting~=false
    end
    function Runtime.ComputerScreen.radioReadOnly()
        if Runtime.dependencies.isNetworkClient then
            return Runtime.dependencies.isNetworkClient()==true
        end
        return Runtime.dependencies.remoteCommand~=nil
    end

    Runtime.PANEL = { x = 52, y = 34, width = 856, height = 610 }
    -- The close control is the X already painted into the browser sprite.
    Runtime.CLOSE = { x = 823, y = 42, width = 27, height = 30 }
    Runtime.BEZEL_CLOCK = { x = 536, y = 646, width = 325, height = 20 }
    Runtime.TABS = {
        { id = "active", label = "ACTIVE JOBS", group = "customers", url = "www.thecritternet.com/job-desk/active" },
        { id = "completed", label = "COMPLETED JOBS", group = "customers", url = "www.thecritternet.com/job-desk/completed" },
        { id = "deliveries", label = "DELIVERIES", group = "customers", url = "www.thecritternet.com/job-desk/deliveries" },
        { id = "estimating", label = "ESTIMATING", group = "customers", url = "www.thecritternet.com/job-desk/estimating" },
        { id = "email", label = "EMAIL", group = "customers", url = "www.thecritternet.com/job-desk/email" },
        { id = "reviews", label = "REVIEWS", group = "customers", url = "www.thecritternet.com/job-desk/reviews" },
        { id = "clock", label = "SHOP CLOCK", group = "shop", url = "www.thecritternet.com/shop/clock" },
        { id = "financials", label = "FINANCIALS", group = "shop", url = "www.thecritternet.com/shop/financials" },
        { id = "receipts", label = "RECEIPTS", group = "shop", url = "www.thecritternet.com/shop/receipts" },
        { id = "inventory", label = "INVENTORY", group = "shop", url = "www.thecritternet.com/job-desk/inventory" },
        { id = "hiring", label = "HIRING", group = "shop", url = "www.thecritternet.com/shop/hiring" },
        { id = "schedule", label = "SCHEDULE", group = "shop", url = "www.thecritternet.com/shop/schedule" },
        { id = "warehouse", label = "WAREHOUSE", group = "shop", url = "www.thecritternet.com/warehouse" },
        { id = "radio", label = "RADIO", group = "shop", url = "www.thecritternet.com/shop/radio" },
        { id = "calendar", label = "CALENDAR", group = "office", url = "www.thecritternet.com/job-desk/calendar" },
        { id = "www", label = "CRITTERNET WWW", group = "office", url = "www.thecritternet.com" },
        { id = "credit", label = "CREDIT", group = "office", url = "www.thecritternet.com/job-desk/credit" },
        { id = "home", label = "MY HOME", group = "office", url = "www.thecritternet.com/my-home" },
        { id = "groceries", label = "GROCERIES", group = "office", url = "www.thecritternet.com/groceries" },
        { id = "takeout", label = "TAKEOUT", group = "office", url = "www.thecritternet.com/takeout" },
        { id = "home_orders", label = "HOME DELIVERIES", group = "office", url = "www.thecritternet.com/home-deliveries" },
        { id = "furniture", label = "HOME & LIVING", group = "office", url = "www.thecritternet.com/home-and-living" },
    }
    Runtime.TAB_GROUPS = {
        { id = "customers", label = "CUSTOMERS" },
        { id = "shop", label = "SHOP" },
        { id = "office", label = "OFFICE" },
    }
    Runtime.TAB_ADDRESS = { x = 170, y = 136, width = 478, height = 40 }
    Runtime.TAB_DROPDOWN_ARROW = { x = 648, y = 136, width = 40, height = 40 }
    Runtime.TAB_DROPDOWN = { x = 170, y = 179, width = 518, rowHeight = 33, headerHeight = 28 }
    Runtime.LIST = { x = 82, y = 190, width = 310, height = 370 }
    Runtime.DETAIL = { x = 412, y = 190, width = 440, height = 444 }
    Runtime.PREVIOUS = { x = 82, y = 570, width = 86, height = 30 }
    Runtime.NEXT = { x = 306, y = 570, width = 86, height = 30 }
    Runtime.COMPLETE = { x = 598, y = 598, width = 228, height = 36 }
    Runtime.PICKUP_EMPLOYEE = { x = 632, y = 598, width = 104, height = 36 }
    Runtime.PICKUP_PLAYER = { x = 742, y = 598, width = 108, height = 36 }
    Runtime.MONITOR = { x = 16, y = 8, width = 928, height = 660 }
    Runtime.WWW_SITE = { x = 116, y = 238, width = 112, height = 42, gap = 8 }
    Runtime.WWW_PRODUCT = { x = 116, y = 296, width = 722, rowHeight = 52, gap = 6 }
    Runtime.WWW_SITES = {
        { name = "PAPER DEPOT", short = "PAPER", url = "www.thecritternet.com/paper-depot", categoryIndex = 1 },
        { name = "PRESSROOM SUPPLY", short = "PRESS", url = "www.thecritternet.com/pressroom", categoryIndex = 2 },
        { name = "CARTON & WRAP", short = "PACKING", url = "www.thecritternet.com/cartons", categoryIndex = 3 },
        { name = "WRENCHWORKS", short = "TOOLS", url = "www.thecritternet.com/tools", categoryIndex = 4 },
        { name = "MACHINE MARKET", short = "MACHINES", url = "www.thecritternet.com/machines", kind = "machines" },
        { name = "VEHICLE DEALER", short = "VEHICLES", url = "www.thecritternet.com/vehicles", kind = "vehicles" },
    }
    Runtime.CART_BUTTON = { x = 714, y = 194, width = 126, height = 36 }
    Runtime.CART_BACK = { x = 116, y = 540, width = 126, height = 40 }
    Runtime.CART_CLEAR = { x = 252, y = 540, width = 126, height = 40 }
    Runtime.CART_CHECKOUT = { x = 648, y = 540, width = 190, height = 40 }
    Runtime.CART_PREVIOUS = { x = 410, y = 544, width = 42, height = 32 }
    Runtime.CART_NEXT = { x = 516, y = 544, width = 42, height = 32 }
    Runtime.CART_PAGE_SIZE = 7
    Runtime.PAY_BILLS = { x = 612, y = 508, width = 196, height = 42 }
    Runtime.EMAIL_QUOTE_INPUT = { x = 434, y = 484, width = 186, height = 36 }
    Runtime.EMAIL_DELIVERY_QUOTE_INPUT = { x = 640, y = 484, width = 186, height = 36 }
    Runtime.EMAIL_DELIVERY_TOGGLE = { x = 434, y = 444, width = 392, height = 20 }
    Runtime.EMAIL_ESTIMATE_SEND = { x = 640, y = 540, width = 186, height = 44 }
    Runtime.EMAIL_ESTIMATE_DECLINE = { x = 434, y = 540, width = 186, height = 44 }
    Runtime.EMAIL_ACCEPT = { x = 640, y = 470, width = 186, height = 40 }
    Runtime.EMAIL_DECLINE = { x = 434, y = 526, width = 186, height = 44 }
    Runtime.EMAIL_DELETE = { x = 640, y = 526, width = 186, height = 44 }
    Runtime.EMAIL_FOLDER_INBOX = { x = 116, y = 218, width = 128, height = 28 }
    Runtime.EMAIL_FOLDER_ARCHIVE = { x = 252, y = 218, width = 144, height = 28 }
    Runtime.EMAIL_PREVIOUS = { x = 116, y = 550, width = 82, height = 28 }
    Runtime.EMAIL_NEXT = { x = 314, y = 550, width = 82, height = 28 }
    Runtime.EMAIL_PAGE_SIZE = 5
    Runtime.PROMO_CANCEL = Runtime.EMAIL_DECLINE
    Runtime.PROMO = { x = 640, y = 526, width = 186, height = 44 }
    Runtime.JOB_PROMO = { x = 640, y = 590, width = 186, height = 44 }
    Runtime.PROMO_INPUT = { x = 434, y = 338, width = 392, height = 122 }
    Runtime.CAL_PANEL = { x = 110, y = 190, width = 738, height = 394 }
    Runtime.CAL_PREVIOUS = { x = 116, y = 202, width = 42, height = 30 }
    Runtime.CAL_NEXT = { x = 800, y = 202, width = 42, height = 30 }
    Runtime.CAL_GRID = { x = 116, y = 272, cellWidth = 104, cellHeight = 52 }
    Runtime.CAL_DAY_DIALOG = { x = 112, y = 190, width = 736, height = 394 }
    Runtime.CAL_DAY_CLOSE = { x = 794, y = 199, width = 38, height = 30 }
    Runtime.CAL_DAY_LIST = { visibleRows = 5, rowHeight = 45,
        shop = { x = 128, y = 266, width = 430, height = 264 },
        town = { x = 572, y = 266, width = 260, height = 264 } }
    Runtime.CAL_DAY_SCROLL_UP = { x = 460, y = 541, width = 44, height = 24 }
    Runtime.CAL_DAY_SCROLL_DOWN = { x = 510, y = 541, width = 48, height = 24 }
    Runtime.MACHINE_OFFER = { x = 116, y = 304, width = 354, height = 50, gap = 5 }
    Runtime.OWNED_MACHINE = { x = 484, y = 304, width = 354, height = 56, gap = 5 }
    Runtime.ComputerScreen.machinePageSize = 4
    Runtime.ComputerScreen.machinePreviousRect = { x = 490, y = 548, width = 78, height = 28 }
    Runtime.ComputerScreen.machineNextRect = { x = 760, y = 548, width = 78, height = 28 }
    Runtime.ROW_HEIGHT = 46
    Runtime.JOBS_PER_PAGE = 7

    -- The approved job desk spacing is shared by its active, completed and delivery views.
    Runtime.ACTIVE_JOB_RECTS = {
        LIST = { x = 116, y = 194, width = 282, height = 352 },
        DETAIL = { x = 410, y = 194, width = 438, height = 390 },
        PREVIOUS = { x = 116, y = 552, width = 76, height = 30 },
        NEXT = { x = 322, y = 552, width = 76, height = 30 },
        COMPLETE = { x = 600, y = 546, width = 236, height = 30 },
        PICKUP_EMPLOYEE = { x = 600, y = 546, width = 104, height = 30 },
        PICKUP_PLAYER = { x = 710, y = 546, width = 126, height = 30 },
        JOB_PROMO = { x = 636, y = 546, width = 200, height = 30 },
    }
    function Runtime.isJobDeskTab()
        local tab = Runtime.ComputerScreen.tab
        return tab == 'active' or tab == 'completed' or tab == 'deliveries'
    end
    function Runtime.jobRect(name)
        return Runtime.isJobDeskTab() and Runtime.ACTIVE_JOB_RECTS[name] or Runtime[name]
    end
    function Runtime.jobRowRect(row)
        local list = Runtime.jobRect('LIST')
        local active = Runtime.isJobDeskTab()
        return { x = list.x + 8, y = list.y + (active and 10 or 14) + (row - 1) * (active and 66 or Runtime.ROW_HEIGHT),
            width = list.width - 16, height = active and 60 or 38 }
    end
    function Runtime.jobsPerPage()
        return Runtime.isJobDeskTab() and 5 or Runtime.JOBS_PER_PAGE
    end

    Runtime.contains, Runtime.commaNumber, Runtime.money = Runtime.Ui.contains, Runtime.Ui.commaNumber, Runtime.Ui.money

    -- Legacy office tools share the CRT content window. Their internal grids
    -- stay intact while draw and input use the same contained coordinates.
    Runtime.HIRING_PAGE_LAYOUT = {x=31.6,y=17.4,sx=.956,sy=.9054}
    Runtime.SCHEDULE_PAGE_LAYOUT = {x=31.7,y=21.1,sx=.932,sy=.908}
    Runtime.HOME_PAGE_LAYOUT = {x=33.6,y=13.45,sx=.932,sy=.929,fontSize=13}
    Runtime.RADIO_PAGE_LAYOUT = {x=33.6,y=21.5,sx=.932,sy=.887,fontSize=14}
    Runtime.WAREHOUSE_PAGE_LAYOUT = {x=31.6,y=9.5,sx=.956,sy=.95,fontSize=13}
    Runtime.WAREHOUSE_STAGING_LAYOUT = {x=55.25,y=18.2,sx=.883,sy=.901,fontSize=14}
    function Runtime.containedPageCoords(x,y,layout)
        return layout.x+x*layout.sx,layout.y+y*layout.sy
    end
    function Runtime.containedPagePoint(x,y,layout)
        if not x or not y then return nil,nil end
        return (x-layout.x)/layout.sx,(y-layout.y)/layout.sy
    end
    function Runtime.drawContainedPage(draw,pointerX,pointerY,layout)
        local ix,iy=Runtime.containedPagePoint(pointerX,pointerY,layout)
        local oldX,oldY=Runtime.buttonDrawPointerX,Runtime.buttonDrawPointerY
        love.graphics.push('all')
        love.graphics.translate(layout.x,layout.y)
        love.graphics.scale(layout.sx,layout.sy)
        love.graphics.setFont(require('src.screens.computer.fonts').get('sans',layout.fontSize or 14))
        Runtime.buttonDrawPointerX,Runtime.buttonDrawPointerY=ix,iy
        draw(ix,iy)
        Runtime.buttonDrawPointerX,Runtime.buttonDrawPointerY=oldX,oldY
        love.graphics.pop()
    end

    Runtime.WAREHOUSE_BAYS = { "front_left", "front_right" }
    Runtime.WAREHOUSE_OPTIONS = { "floor", "storage", "breakroom" }
    Runtime.WAREHOUSE_FORKLIFT = {x=670,y=490,width=164,height=40}
    Runtime.WAREHOUSE_CONFIRM = {x=508,y=514,width=228,height=40}
    Runtime.WAREHOUSE_CANCEL = {x=216,y=514,width=180,height=40}
    Runtime.WAREHOUSE_ACK = {x=206,y=430,width=542,height=48}
    Runtime.CREDIT_MACHINE = { x = 116, y = 306, width = 332, height = 66, gap = 4 }
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
