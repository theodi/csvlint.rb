require "webmock/cucumber"

WebMock.disable_net_connect!(allow: %r{csvw/tests})
