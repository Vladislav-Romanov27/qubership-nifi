#!/bin/bash -e
# Copyright 2020-2025 NetCracker Technology Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# shellcheck source=/dev/null
. /opt/nifi/scripts/logging_api.sh

"$JAVA_HOME"/bin/java ${CONSUL_CONFIG_JAVA_OPTIONS} -jar "$NIFI_HOME"/utility-lib/qubership-consul-application.jar org.qubership.cloud.nifi.config.NifiPropertiesLookup &

consul_pid=$!
#info "consul_pid=$consul_pid"