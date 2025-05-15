-include .env

# Define .PHONY to ensure these targets always run regardless of file existence
.PHONY: update build size test trace gas deploy deploy-trace clean

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# specify which network to use from .env
SEPOLIA_URL := ${SEPOLIA_RPC}

# if we want to run only matching tests, set that here
test_pattern := test_

# Tests
test  :; forge test -vv --fork-url ${SEPOLIA_URL}
trace  :; forge test -vvv --fork-url ${SEPOLIA_URL}
gas  :; forge test --fork-url ${SEPOLIA_URL} --gas-report
test-match  :; forge test -vv --match-test $(test_pattern) --fork-url ${SEPOLIA_URL}

# Deployment scripts
deploy  :; forge script ./script/BatchCallAndSponsor.s.sol --tc BatchCallAndSponsorScript --broadcast --rpc-url ${SEPOLIA_URL}
deploy-trace  :; forge script ./script/BatchCallAndSponsor.s.sol --tc BatchCallAndSponsorScript --broadcast --rpc-url ${SEPOLIA_URL} -vvvv

# clean
clean  :; forge clean
