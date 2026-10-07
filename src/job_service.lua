-- Components share one private context and preserve the public JobService API.
local Runtime = {}
require("src.job_service.catalog").install(Runtime)
require("src.job_service.repeat_jobs").install(Runtime)
require("src.job_service.inbox").install(Runtime)
require("src.job_service.quotes").install(Runtime)
require("src.job_service.promotions").install(Runtime)
require("src.job_service.offers").install(Runtime)
require("src.job_service.pickup").install(Runtime)

return Runtime.JobService
