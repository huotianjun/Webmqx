PROJECT = webmqx
PROJECT_DESCRIPTION = New project
PROJECT_VERSION = 0.0.1

DEPS = cowboy riakc amqp_client rabbit jiffy
LOCAL_DEPS = ssl observer runtime_tools
dep_cowboy_commit = master

include erlang.mk
