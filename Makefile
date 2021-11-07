MAKEFILE_VERSION := 2021-08-17--01
MAKEFILE_VERSION_CHECK := yes
REMOTE_VERSION := $(shell curl -s "https://gist.githubusercontent.com/eieste/3c421b77254895ebfc516d493c06518a/raw/VERSION")

ifndef VERBOSE
.SILENT:
endif


CURRENT_DIR = $(shell pwd)
PARAMETER_FILE ?=
PARAM_CHECK ?= $(PARAMETER_FILE)

VALIDATION_CFN_IGNORE := -i W2001

ifneq (, $(PARAM_CHECK))
	UNIQUE_EXTENSION := $(shell yq -r '.Parameters.UniqueExtension' ./parameters/$(PARAMETER_FILE))
	PREFIX := $(shell yq -r '.Parameters.Prefix' ./parameters/$(PARAMETER_FILE))
	PROJECT_SLUG := $(shell yq -r '.Parameters.ProjectSlug' ./parameters/$(PARAMETER_FILE))
	STACK_SLUG := $(shell yq -r '.Parameters.StackSlug' ./parameters/$(PARAMETER_FILE))
	SEED_STACK_NAME := $(shell yq -r .Parameters.SeedStackName  ./parameters/$(PARAMETER_FILE))
	SEED_BUCKET_NAME := $(shell aws cloudformation describe-stacks --stack-name $(SEED_STACK_NAME) | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "SeedBucketName").OutputValue')
	ENVIRONMENT := $(shell yq -r '.Parameters | if has("EnvironmentName") then .EnvironmentName else "false" end' ./parameters/$(PARAMETER_FILE))
	CIDASH_TOPIC_ARN := $(shell aws cloudformation list-exports | jq -r '.Exports[] | select(.Name == "cidashTopicArn") | .Value' - )
	NOTIFICATION_TOPIC_ARN ?= $(shell yq -r '.Parameters | if has("CfnNotificationTopicArn") then .CfnNotificationTopicArn else "$(CIDASH_TOPIC_ARN)" end' ./parameters/$(PARAMETER_FILE) )
else
	UNIQUE_EXTENSION :=
	PREFIX :=
	PROJECT_SLUG :=
	STACK_SLUG :=
	ENVIRONMENT :=
	CIDASH_TOPIC_ARN :=
	NOTIFICATION_TOPIC_ARN ?=
endif

ifeq ($(ENVIRONMENT), false)
	STACK_NAME := $(PREFIX)-$(PROJECT_SLUG)-$(STACK_SLUG)-$(UNIQUE_EXTENSION)
	UPLOAD_PATH := $(SEED_BUCKET_NAME)/$(PREFIX)/$(PROJECT_SLUG)/$(STACK_SLUG)/$(UNIQUE_EXTENSION)/$(STACK_NAME)
else
	STACK_NAME := $(PREFIX)-$(ENVIRONMENT)-$(PROJECT_SLUG)-$(STACK_SLUG)-$(UNIQUE_EXTENSION)
	UPLOAD_PATH := $(SEED_BUCKET_NAME)/$(PREFIX)/$(ENVIRONMENT)/$(PROJECT_SLUG)/$(STACK_SLUG)/$(UNIQUE_EXTENSION)/$(STACK_NAME)
endif


.SILENT:


ifeq ($(NOTIFICATION_TOPIC_ARN), )
	NOTIFICATION_PARAEMETER :=
else
	NOTIFICATION_PARAMETER := --notification-arns $(NOTIFICATION_TOPIC_ARN)
endif


AWS_STACK_PARAMETER := --stack-name $(STACK_NAME) \
	--template-body file://$(CURRENT_DIR)/stack.cfn.yml \
	--parameters file://$(CURRENT_DIR)/parameter.json $(NOTIFICATION_PARAMETER) \
	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

makefile_version_check:
ifeq ($(MAKEFILE_VERSION_CHECK), yes)
ifneq ($(MAKEFILE_VERSION), $(REMOTE_VERSION))
	@echo "Remote Version ( $(REMOTE_VERSION) ) doesnt match with Local Version ( $(MAKEFILE_VERSION) )"
endif
endif

init:
	npm install -y
	./node_modules/.bin/husky install


validate: makefile_version_check
# stack/cloudtrail.yml stack/sns2slack.yml
	yamllint parameters/*.yml
	for file in "`find ./ -type f  -name '*.cfn.yml'`" ; do \
  		echo $$file; \
		cfn-lint $(VALIDATION_CFN_IGNORE) -t $(CURRENT_DIR)/$$file; \
	done


build: build-rah

build-rah:
	mkdir -p build/
	make -C rah/ build
	cp -r rah/build/* ./build/


copy:
	echo $(UPLOAD_PATH)
	aws s3 sync --exclude ".git/**" --exclude "node_modules/**" --exclude ".idea/**" --exclude "**/node_modules/**" --exclude "**/__pycache__/**" ./ s3://$(UPLOAD_PATH)

deploy: makefile_version_check build build-parameter validate copy
	aws cloudformation create-stack $(AWS_STACK_PARAMETER)

deploy-only: build-parameter validate copy
	aws cloudformation create-stack $(AWS_STACK_PARAMETER)

update: makefile_version_check build build-parameter validate copy
	aws cloudformation update-stack $(AWS_STACK_PARAMETER)

update-only: makefile_version_check build-parameter validate copy
	aws cloudformation update-stack $(AWS_STACK_PARAMETER)

remove: makefile_version_check makefile_version_check
	aws cloudformation delete-stack --stack-name $(STACK_NAME)

update-lambda: makefile_version_check build-sns2slack
	aws lambda update-function-code --zip-file fileb://$(CURRENT_DIR)/sns2slack.zip --function-name $(LAMBDA_NAME)

build-parameter: makefile_version_check
	cat parameters/$(PARAMETER_FILE) | \
	       	yq .Parameters | \
		jq '[ . | to_entries | .[] | { "ParameterKey": .key, "ParameterValue": .value| (if type == "array" then join(",") else . end)  } ]' | \
	       	tee parameter.json

set-version: makefile_version_check
	npm  --no-git version --allow-same-version --no-git --no-git-tag-version $(VERSION)
	echo $(VERSION) > VERSION


clean:
	rm -Rf tmp/
	rm -Rf build/
	rm -RF node_moudles/
	rm parameter*.json
