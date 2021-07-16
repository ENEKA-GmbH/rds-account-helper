CURRENT_DIR = $(shell pwd)

PARAMETER_FILE ?= ""

PROJECT_SLUG := $(shell yq -r .Parameters.ProjectSlug ./parameter_$(PARAMETER_FILE).yml)
NAME := $(shell yq -r .Parameters.Name ./parameter_$(PARAMETER_FILE).yml)
SEED_STACK_NAME := $(shell yq -r .Parameters.SeedStackName  ./parameter_$(PARAMETER_FILE).yml)
SEED_BUCKET_NAME := $(shell aws cloudformation describe-stacks --stack-name $(SEED_STACK_NAME) | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "SeedBucketName").OutputValue')
UNIQUE_EXTENSION := $(shell yq -r .Parameters.UniqueExtension  ./parameter_$(PARAMETER_FILE).yml)
ENVIRONMENT := $(shell yq -r .Parameters.Environment  ./parameter_$(PARAMETER_FILE).yml)

PREFIX := $(shell yq -r .Parameters.Prefix  ./parameter_$(PARAMETER_FILE).yml)

STACK_NAME = $(PREFIX)-$(PROJECT_SLUG)-$(ENVIRONMENT)-$(NAME)-$(UNIQUE_EXTENSION)


init:
	npm install -y
	./node_modules/.bin/husky install


validate:
	aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack.yml
	aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack/cloudtrail.yml
	yamllint ./parameter_kommek.yml
	

copy:
	aws s3 sync --exclude ".git/**" --exclude "node_modules/**" ./ s3://$(SEED_BUCKET_NAME)/$(PREFIX)/$(PROJECT_SLUG)/$(ENVIRONMENT)/$(STACK_NAME)/$(UNIQUE_EXTENSION)/$(STACK_NAME)


deploy: build-parameter copy
	aws cloudformation create-stack --stack-name $(STACK_NAME) \
	--template-body file://$(CURRENT_DIR)/stack.yml \
	--parameters file://$(CURRENT_DIR)/parameter_$(PARAMETER_FILE).json \
	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

build-parameter:
	cat parameter_$(PARAMETER_FILE).yml | yq .Parameters | jq '[ . | to_entries | .[] | { "ParameterKey": .key, "ParameterValue": .value| (if type == "array" then join(",") else . end)  } ]' |  tee parameter_$(PARAMETER_FILE).json


update: build-parameter copy
	aws cloudformation update-stack --stack-name $(STACK_NAME) \
	--template-body file://$(CURRENT_DIR)/stack.yml \
	--parameters file://$(CURRENT_DIR)/parameter_$(PARAMETER_FILE).json \
	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

