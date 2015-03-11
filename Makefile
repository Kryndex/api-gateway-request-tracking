# NOTE: Every line in a recipe must begin with a tab character.
BUILD_DIR ?= target
REDIS_VERSION ?= 2.8.6

PREFIX ?=          /usr/local
LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL ?= install
TEST_NGINX_AWS_CLIENT_ID ?= ''
TEST_NGINX_AWS_SECRET ?= ''

.PHONY: all clean test install

all: ;

install: all
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/tracking/
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/tracking/log/
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/tracking/validator/
	$(INSTALL) src/lua/api-gateway/tracking/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/tracking/
	$(INSTALL) src/lua/api-gateway/tracking/log/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/tracking/log/
	$(INSTALL) src/lua/api-gateway/tracking/validator/*.lua $(DESTDIR)/$(LUA_LIB_DIR)/api-gateway/tracking/validator/

test: redis
	echo "updating git submodules ..."
	if [ ! -d "test/resources/test-nginx/lib" ]; then	git submodule update --init --recursive; fi
	echo "running tests ..."
	mkdir  -p $(BUILD_DIR)
	mkdir  -p $(BUILD_DIR)/test-logs
	cp -r test/resources/api-gateway $(BUILD_DIR)
	rm -f $(BUILD_DIR)/test-logs/*

	PATH=/usr/local/sbin:$$PATH TEST_NGINX_SERVROOT=`pwd`/$(BUILD_DIR)/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl
	cat $(BUILD_DIR)/redis-test.pid | xargs kill

redis: all
	mkdir -p $(BUILD_DIR)
	tar -xf test/resources/redis/redis-$(REDIS_VERSION).tar.gz -C $(BUILD_DIR)/
	cd $(BUILD_DIR)/redis-$(REDIS_VERSION) && make

package:
	git archive --format=tar --prefix=api-gateway-request-tracking-1.0/ -o api-gateway-request-tracking-1.0.tar.gz -v HEAD

clean: all
	rm -rf $(BUILD_DIR)