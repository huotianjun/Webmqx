PROJECT = rabbitmq_webmqx

DEPS = amqp_client cowboy jiffy

LOCAL_DEPS = ssl observer runtime_tools

dep_cowboy_commit = master

DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk

include erlang.mk
