# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 10) - 1;

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path "src/lua/?.lua;/usr/local/lib/lua/?.lua;;";
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
     init_worker_by_lua '
        ngx.apiGateway = ngx.apiGateway or {}
        ngx.apiGateway.validation = require "api-gateway.validation.factory"
        ngx.apiGateway.tracking = require "api-gateway.tracking.factory"
     ';
    include "$pwd/conf.d/http.d/*.conf";
    upstream cache_rw_backend {
    	server 127.0.0.1:6379;
    }
    upstream cache_read_only_backend { # Default config for redis health check test
        server 127.0.0.1:6379;
    }
    lua_shared_dict blocking_rules_dict 5m;
    lua_shared_dict tracking_rules_dict 5m;
    lua_shared_dict debugging_rules_dict 5m;
    lua_shared_dict delaying_rules_dict 5m;
    lua_shared_dict retrying_rules_dict 5m;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: test that there are no default rules
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/tracking_service.conf;
        error_log ../test-logs/requestTrackingManager_test1_error.log warn;
--- more_headers
X-Test: test
--- request
GET /tracking/track
--- response_body eval
["{}\n"]
--- error_code: 200
--- no_error_log
[error]


=== TEST 2: test that we can add new rules and persist them
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/tracking_service.conf;
        error_log ../test-logs/requestTrackingManager_test2_error.log debug;
--- pipelined_requests eval
['POST /tracking/
{
  "id": 222,
  "domain" : "cc-eco;comcast;*",
  "format": "$publisher_org_name;$consumer_org_name;$api_key",
  "expire_at_utc": 1583910454,
  "action" : "track"
}
',
'POST /tracking/
{
  "id": 223,
  "domain" : "cc-eco;comcast",
  "format": "$publisher_org_name;$consumer_org_name",
  "expire_at_utc": 1583910454,
  "action" : "block"
}
',
"GET /tracking/track",
"GET /tracking/block",
'POST /tracking/
{
  "id": 333,
  "domain" : "cc-eco;comcast;*",
  "format": "$publisher_org_name;$consumer_org_name;$api_plan",
  "expire_at_utc": 1583910454,
  "action" : "track"
}
',
"GET /tracking/track"]
--- response_body eval
[
'{"result":"success"}
',
'{"result":"success"}
',
'[{"domain":"cc-eco;comcast;*","format":"$publisher_org_name;$consumer_org_name;$api_key","id":222,"action":"track","expire_at_utc":"1583910454"}]
',
'[{"domain":"cc-eco;comcast","format":"$publisher_org_name;$consumer_org_name","id":223,"action":"block","expire_at_utc":"1583910454"}]
',
'{"result":"success"}
',
'[{"domain":"cc-eco;comcast;*","format":"$publisher_org_name;$consumer_org_name;$api_key","id":222,"action":"track","expire_at_utc":"1583910454"},{"domain":"cc-eco;comcast;*","format":"$publisher_org_name;$consumer_org_name;$api_plan","id":333,"action":"track","expire_at_utc":"1583910454"}]
'
]
--- error_code_like eval
 [200, 200, 200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 3: test that we can add a batch of rules at once
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/tracking_service.conf;
        error_log ../test-logs/requestTrackingManager_test3_error.log debug;
--- pipelined_requests eval
['POST /tracking/
[{
  "id": 222,
  "domain" : "cc-eco;comcast;*",
  "format": "$publisher_org_name;$consumer_org_name;$api_key",
  "expire_at_utc": 1583910454,
  "action" : "track"
},
{
  "id": 223,
  "domain" : "cc-eco;comcast",
  "format": "$publisher_org_name;$consumer_org_name",
  "expire_at_utc": 1583910454,
  "action" : "block"
}]
',
"GET /tracking/track",
"GET /tracking/block",
'POST /tracking/
[{
  "id": 333,
  "domain" : "cc-eco;comcast;*",
  "format": "$publisher_org_name;$consumer_org_name;$api_plan",
  "expire_at_utc": 1583910454,
  "action" : "track"
},{
  "id": 444,
  "domain" : "cc-eco;comcast;*",
  "format": "$publisher_org_name;$consumer_org_name;$app_name",
  "expire_at_utc": 1583910454,
  "action" : "track"
}
]',
"GET /tracking/track"]
--- response_body eval
[
'{"result":"success"}
',
'[{"domain":"cc-eco;comcast;*","format":"$publisher_org_name;$consumer_org_name;$api_key","id":222,"action":"track","expire_at_utc":"1583910454"}]
',
'[{"domain":"cc-eco;comcast","format":"$publisher_org_name;$consumer_org_name","id":223,"action":"block","expire_at_utc":"1583910454"}]
',
'{"result":"success"}
',
'[{"domain":"cc-eco;comcast;*","format":"$publisher_org_name;$consumer_org_name;$api_key","id":222,"action":"track","expire_at_utc":"1583910454"},{"domain":"cc-eco;comcast;*","format":"$publisher_org_name;$consumer_org_name;$api_plan","id":333,"action":"track","expire_at_utc":"1583910454"},{"domain":"cc-eco;comcast;*","format":"$publisher_org_name;$consumer_org_name;$app_name","id":444,"action":"track","expire_at_utc":"1583910454"}]
'
]
--- error_code_like eval
 [200, 200, 200, 200, 200, 200]
--- no_error_log
[error]



=== TEST 4: test expiration time for the rules
--- http_config eval: $::HttpConfig
--- config
        include ../../api-gateway/tracking_service.conf;
        error_log ../test-logs/requestTrackingManager_test4_error.log debug;

        location /test-expiration {
            set_by_lua $generated_expires_at '
                        local ts = ngx.now()
                        local utcdate   = os.date("!*t", ts)
                        local localdate = os.date("*t", ts)
                        localdate.isdst = false -- this is the trick
                        local offset = os.difftime(os.time(localdate), os.time(utcdate))

                        ngx.log(ngx.WARN, "NGX LOCAL TIME = " .. ngx.localtime() .. ", UTC=" .. ngx.utctime() .. ", ngx.now=" ..ngx.now() .. ", ngx.time=" .. ngx.time() .. ", http_time=" .. ngx.http_time( ngx.time() )  )
                        -- NOTE: assumption is that ngx.now() and ngx.time() is UTC
                        -- expire in 1 second
                        return ( ngx.time() + 1 )
            ';
            set $block_1 '{"domain":"cc-eco;comcast","format":"publisher_org_name;consumer_org_name","id":223,"action":"block","expire_at_utc":$generated_expires_at}';
            content_by_lua '
                local trackingManager = ngx.apiGateway.tracking.manager
                trackingManager:addRule(ngx.var.block_1)
                local blocking_rules = trackingManager:getRulesForType("block")
                assert( table.getn(blocking_rules) == 1, "ONE blocking rule should exists")
                assert( blocking_rules[1]["id"] == 223, "Blocking rule should have been saved")
                ngx.sleep(1.5)
                blocking_rules = trackingManager:getRulesForType("block")
                assert( table.getn(blocking_rules) == 0, "Blocking rules should expire")
                ngx.say("OK")
            ';
        }
--- more_headers
X-Test: test
--- request
GET /test-expiration
--- response_body eval
["OK\n"]
--- error_code: 200
--- no_error_log
[error]



