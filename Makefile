MAKEFILE_VERSION := 2021-07-30--03
MAKEFILE_VERSION_CHECK := yes
REMOTE_VERSION := $(shell curl -s "https://gist.githubusercontent.com/eieste/3c421b77254895ebfc516d493c06518a/raw/VERSION")

ifndef VERBOSE
.SILENT:
endif

NAME := account-service

CURRENT_DIR = $(shell pwd)
PARAMETER_FILE ?= "global.yml"

UNIQUE_EXTENSION := $(shell yq -r '.Parameters.UniqueExtension' ./parameters/$(PARAMETER_FILE))
PREFIX := $(shell yq -r '.Parameters.Prefix' ./parameters/$(PARAMETER_FILE))
PROJECT_SLUG := $(shell yq -r '.Parameters.ProjectSlug' ./parameters/$(PARAMETER_FILE))


SEED_STACK_NAME := $(shell yq -r .Parameters.SeedStackName  ./parameters/$(PARAMETER_FILE))
SEED_BUCKET_NAME := $(shell aws cloudformation describe-stacks --stack-name $(SEED_STACK_NAME) | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "SeedBucketName").OutputValue')

ENVIRONMENT := $(shell yq -r '.Parameters | if has("Environment") then .Environment else "FALSE" end' ./parameters/$(PARAMETER_FILE))
ifeq ($(ENVIRONMENT), FALSE)
	STACK_NAME := $(PREFIX)-$(PROJECT_SLUG)-$(NAME)-$(UNIQUE_EXTENSION)
	UPLOAD_PATH := $(SEED_BUCKET_NAME)/$(PREFIX)/$(PROJECT_SLUG)/$(UNIQUE_EXTENSION)/$(STACK_NAME)
else
	STACK_NAME := $(PREFIX)-$(PROJECT_SLUG)-$(ENVIRONMENT)-$(NAME)-$(UNIQUE_EXTENSION)
	UPLOAD_PATH := $(SEED_BUCKET_NAME)/$(PREFIX)/$(PROJECT_SLUG)/$(ENVIRONMENT)/$(UNIQUE_EXTENSION)/$(STACK_NAME)
endif


.SILENT:


CIDASH_TOPIC_ARN := $(shell aws cloudformation list-exports | jq -r '.Exports[] | select(.Name == "cidashTopicArn") | .Value' - )

NOTIFICATION_TOPIC_ARN ?= $(shell yq -r '.Parameters | if has("CfnNotificationTopicArn") then .CfnNotificationTopicArn else "$(CIDASH_TOPIC_ARN)" end' ./parameters/$(PARAMETER_FILE) )

ifeq ($(NOTIFICATION_TOPIC_ARN), )
	NOTIFICATION_PARAEMETER :=
else
	NOTIFICATION_PARAMETER := --notification-arns $(NOTIFICATION_TOPIC_ARN)
endif


AWS_STACK_PARAMETER := --stack-name $(STACK_NAME) \
	--template-body file://$(CURRENT_DIR)/stack.yml \
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


validate:
	@aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack.yml
	@aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack/cloudtrail.yml
	@aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack/dbmgr.yml
	@aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack/sns2slack.yml
	@aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack/pymysql_lambdalayer.yml
	yamllint ./parameters/*.yml


build: build-pymysql-layer build-dbmgr build-sns2slack

build-pymysql-layer:
	mkdir -p build/
	docker run --rm -it -v "$(CURRENT_DIR)":/var/task amazonlinux:2 /bin/sh -c "yum install -y gcc python3-devel mariadb-devel mariadb mariadb-community-libs amazon-linux-extras python3 make jq awscli; pip3 install virtualenv; cd /var/task; make buildlayer-indocker; exit"

buildlayer-indocker:
	mkdir -p tmp/pymysql/python
	cd tmp/pymysql; \
	python3 -m virtualenv pymysqlvenv; \
	( source pymysqlvenv/bin/activate; pip3 install PyMySql ); \
	cp -r pymysqlvenv/lib/python*/site-packages/pymysql python; \
	zip -r ../../build/pymysql-layer.zip ./python
	rm -rf tmp/ 

build-dbmgr:
	mkdir -p build/
	cd dbmgr/; zip -r ../build/dbmgr.zip ./*

build-sns2slack:
	mkdir -p build/
	cd sns2slack/; zip -r ../build/sns2slack.zip ./*

copy:
	echo $(UPLOAD_PATH)
	aws s3 sync --exclude ".git/**" --exclude "node_modules/**" ./ s3://$(UPLOAD_PATH)

deploy: makefile_version_check build build-parameter copy
	aws cloudformation create-stack $(AWS_STACK_PARAMETER)

deploy-only: build-parameter copy
	aws cloudformation create-stack $(AWS_STACK_PARAMETER)

update: makefile_version_check build build-parameter copy
	aws cloudformation update-stack $(AWS_STACK_PARAMETER)

update-only: makefile_version_check build-parameter copy
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
