PROJECT = webmqx

DEPS = ranch amqp_client cowboy jiffy jsx lager rabbit

LOCAL_DEPS = ssl observer runtime_tools

#dep_cowboy_commit = master 
#dep_cowboy_commit = 2.0.0-pre.3

DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk

include erlang.mk
