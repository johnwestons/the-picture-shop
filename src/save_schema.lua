-- Components share one private context and preserve the public Schema API.
local Runtime = {}
require("src.save_schema.primitives").install(Runtime)
require("src.save_schema.paper").install(Runtime)
require("src.save_schema.jobs").install(Runtime)
require("src.save_schema.inventory").install(Runtime)
require("src.save_schema.physical").install(Runtime)
require("src.save_schema.defaults").install(Runtime)
require("src.save_schema.job_migration").install(Runtime)
require("src.save_schema.state_migration").install(Runtime)
require("src.save_schema.payload").install(Runtime)

return Runtime.Schema
