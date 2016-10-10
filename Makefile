PROJECT = webmqx

DEPS = amqp_client cowboy jiffy rabbit

LOCAL_DEPS = ssl observer runtime_tools

## 用master可能会有问题
dep_cowboy_commit = master 

##huotianjun 增加了rabbitmq plugins用到的makefile内容
DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

##huotianjun 这个是rabbitmq对erlang.mk加的重定向erlang.mk到rabbitmq定义的erlang.mk，似乎修改了什么。不能用标准的erlang,mk
ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk

include erlang.mk
