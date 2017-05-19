PROJECT = webmqx

DEPS = amqp_client cowboy jiffy jsx rabbit_common rabbit

LOCAL_DEPS = ssl observer runtime_tools

#dep_cowboy_commit = master 
#dep_cowboy_commit = 2.0.0-pre.3

DEP_EARLY_PLUGINS = rabbit_common/mk/rabbitmq-early-plugin.mk
DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk

include erlang.mk
