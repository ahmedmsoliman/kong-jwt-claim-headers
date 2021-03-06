local BasePlugin = require "kong.plugins.base_plugin"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local JWT_PLUGIN_PRIORITY = (require "kong.plugins.jwt.handler").PRIORITY

local MAPPED_HEADER_PREFIX = "X-Consumer-"

local ngx_set_header = ngx.req.set_header
local ngx_re_gmatch = ngx.re.gmatch

local JwtClaimHeadersHandler = BasePlugin:extend()

-- Set this plugin to execute after the default jwt plugin provided by Kong
-- Plugins with higher priority are executed first
JwtClaimHeadersHandler.PRIORITY = JWT_PLUGIN_PRIORITY - 100

local function retrieve_token(request, conf)
  local authorization_header = request.get_headers()["authorization"]
  if authorization_header then
    local iterator, iter_err = ngx_re_gmatch(authorization_header, "\\s*[Bb]earer\\s+(.+)")
    if not iterator then
      return nil, iter_err
    end

    local m, err = iterator()
    if err then
      return nil, err
    end

    if m and #m > 0 then
      return m[1]
    end
  end
end

function JwtClaimHeadersHandler:new()
  JwtClaimHeadersHandler.super.new(self, "jwt-claim-headers")
end

function JwtClaimHeadersHandler:access(conf)
  JwtClaimHeadersHandler.super.access(self)

  local token, err = retrieve_token(ngx.req, conf)
  if err or not token then
    return kong.response.exit(401, [[{"message":"unauthorized"}]], {
      ["Content-Type"] = "application/json",
    })
  end

  local jwt, err = jwt_decoder:new(token)
  -- Now verify the JWT signature
  if not jwt:verify_signature(conf.jwt_secret) or err then
    return kong.response.exit(401, [[{"message":"unauthorized"}]], {
      ["Content-Type"] = "application/json",
    })  end

  local claims = jwt.claims

  for claim_key, claim_value in pairs(claims) do
      ngx_set_header(MAPPED_HEADER_PREFIX .. claim_key, claim_value)
  end
end

return JwtClaimHeadersHandler
