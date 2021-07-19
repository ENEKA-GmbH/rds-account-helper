CURRENT_DIR = $(shell pwd)
ENV_ENUM := development staging release
PARAMETER_FILE ?= "global"

PROJECT_SLUG := $(shell yq -r .Parameters.ProjectSlug ./parameter_$(PARAMETER_FILE).yml)
NAME := $(shell yq -r .Parameters.Name ./parameter_$(PARAMETER_FILE).yml)
SEED_STACK_NAME := $(shell yq -r .Parameters.SeedStackName  ./parameter_$(PARAMETER_FILE).yml)
SEED_BUCKET_NAME := $(shell aws cloudformation describe-stacks --stack-name $(SEED_STACK_NAME) | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "SeedBucketName").OutputValue')
CFN_ROLE := $(shell aws cloudformation describe-stacks --stack-name $(SEED_STACK_NAME) | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "CloudformationRoleArn").OutputValue')


GLOBAL_SNS_TOPIC_CFN_ARN = $(shell yq -r .Parameters.GlobalSnsTopicCfn ./parameter_$(PARAMETER_FILE).yml)
UNIQUE_EXTENSION := $(shell yq -r .Parameters.UniqueExtension  ./parameter_$(PARAMETER_FILE).yml)
ENVIRONMENT := $(shell yq -r .Parameters.Environment  ./parameter_$(PARAMETER_FILE).yml)

PREFIX := $(shell yq -r .Parameters.Prefix  ./parameter_$(PARAMETER_FILE).yml)

STACK_NAME = $(PREFIX)-$(PROJECT_SLUG)-$(ENVIRONMENT)-$(NAME)-$(UNIQUE_EXTENSION)

LAMBDA_NAME = $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "Sns2SlackFunctionName").OutputValue')

ifeq ($(filter $(ENVIRONMENT),$(ENV_ENUM)),)
    $(error $(ENVIRONMENT) ist a valid name for environment. allowed environments are $(ENV_ENUM))
endif


init:
	npm install -y
	./node_modules/.bin/husky install


validate:
	aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack.yml
	aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/stack/cloudtrail.yml
	yamllint ./parameter_kommek.yml


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

copy: build 
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


update-lambda: build-sns2slack
	aws lambda update-function-code --zip-file fileb://$(CURRENT_DIR)/sns2slack.zip --function-name $(LAMBDA_NAME)


clean:
	rm -Rf tmp/
	rm -Rf build/
	rm -RF node_moudles/
	rm parameter*.json
