# Environment for Patrol + Allure runs (copied template)
# Adjust values for your project.

export APP_VERSION="1.0"
export FLAVOR="prod"
export APP_ENV="prod"
export BASE_URL="jsxhc7emf3.execute-api.eu-west-1.amazonaws.com"  # change to your API host
export GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo '')"

export PATROL_CONFIG_JSON=""
export FEATURE_FLAGS_TEXT=""

export PLATFORM="${PLATFORM:-auto}"
export TAGS=""
export EXCLUDE_TAGS=""

export ALLURE_XCRESULT_BIN=""
export ALLURE_XCRESULT_REPO=""
