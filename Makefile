CURRENT_DIR := $(shell pwd)
VALIDATION_CFN_IGNORE := -i W2001

ifndef STACK_DIR
$(error STACK_DIR is not set)
endif

ifndef PARAMETER_FILE
$(error PARAMETER_FILE is not set)
endif

DATE := $(shell date '+%d-%m-%Y--%H-%M-%S');

PREFIX := $(shell yq e '.Parameters.Prefix' $(PARAMETER_FILE))
ENVIRONMENT := $(shell yq e '.Parameters.EnvironmentName' $(PARAMETER_FILE))

PROJECT_SLUG := $(shell yq e '.Parameters.ProjectSlug' $(PARAMETER_FILE))
STACK_SLUG := $(shell yq e '.Parameters.StackSlug' $(PARAMETER_FILE))
UNIQUE_EXTENSION := $(shell yq e '.Parameters.UniqueExtension' $(PARAMETER_FILE))

SEED_STACK_NAME = $(shell yq e .Parameters.SeedStackName $(PARAMETER_FILE))
SEED_BUCKET_NAME = $(shell aws cloudformation describe-stacks --stack-name $(SEED_STACK_NAME) | jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "SeedBucketName").OutputValue')

STACK_NAME := $(PREFIX)-$(ENVIRONMENT)-$(PROJECT_SLUG)-$(STACK_SLUG)-$(UNIQUE_EXTENSION)



ifeq ($(ENVIRONMENT), false)
	STACK_NAME := $(PREFIX)-$(PROJECT_SLUG)-$(STACK_SLUG)-$(UNIQUE_EXTENSION)
	UPLOAD_PATH := $(SEED_BUCKET_NAME)/$(PREFIX)/$(PROJECT_SLUG)/$(STACK_SLUG)/$(UNIQUE_EXTENSION)/$(STACK_NAME)
else
	STACK_NAME := $(PREFIX)-$(ENVIRONMENT)-$(PROJECT_SLUG)-$(STACK_SLUG)-$(UNIQUE_EXTENSION)
	UPLOAD_PATH := $(SEED_BUCKET_NAME)/$(PREFIX)/$(ENVIRONMENT)/$(PROJECT_SLUG)/$(STACK_SLUG)/$(UNIQUE_EXTENSION)/$(STACK_NAME)
endif





AWS_STACK_PARAMETER := --stack-name $(STACK_NAME) \
	--template-body file://$(CURRENT_DIR)/stack.cfn.yml \
	--parameters file://$(CURRENT_DIR)/parameter.json \
	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

init:
	npm install -y
	./node_modules/.bin/husky install


validate:
	yamllint parameters/*.yml
	for file in $(find ./ -type f -iname "*.cfn.yml") ; do \
		cfn-lint $(VALIDATION_CFN_IGNORE) -t $(CURRENT_DIR)/$$file; \
	done
	# aws cloudformation validate-template --template-body file://$(CURRENT_DIR)/$$file --output text


build: build-rah

build-rah:
	mkdir -p build/
	make -C rah/ build
	cp -r rah/build/* ./build/

copy:
	echo $(UPLOAD_PATH)
	aws s3 sync --exclude ".git/**" --exclude "node_modules/**" --exclude ".idea/**" --exclude "**/node_modules/**" --exclude "**/__pycache__/**" ./ s3://$(UPLOAD_PATH)

deploy: build build-parameter validate copy
	aws cloudformation create-stack $(AWS_STACK_PARAMETER)

deploy-only: build-parameter validate copy
	aws cloudformation create-stack $(AWS_STACK_PARAMETER)

update: build build-parameter validate copy
	aws cloudformation update-stack $(AWS_STACK_PARAMETER)

update-only: build-parameter validate copy
	aws cloudformation update-stack $(AWS_STACK_PARAMETER)

remove:
	aws cloudformation delete-stack --stack-name $(STACK_NAME)

update-lambda: build-sns2slack
	aws lambda update-function-code --zip-file fileb://$(CURRENT_DIR)/sns2slack.zip --function-name $(LAMBDA_NAME)
#
#build-parameter:
#	cat parameters/$(PARAMETER_FILE) | \
#	       	yq .Parameters | \
#		jq '[ . | to_entries | .[] | { "ParameterKey": .key, "ParameterValue": .value| (if type == "array" then join(",") else . end)  } ]' | \
#	       	tee parameter.json

build-parameter:
	# yq ea  "select(fileIndex == 0) * select(fileIndex == 1)" $(PARAMETER_FILE) $(CURRENT_DIR)/global.parameter.yml | \
	yq ea -o json '.Parameters' $(PARAMETER_FILE) | \
	jq '[ . | to_entries | .[] | { "ParameterKey": .key, "ParameterValue": .value| (if type == "array" then join(",") else . end)  } ]' | \
	tee $(STACK_DIR)/parameter.json

set-version:
	npm  --no-git version --allow-same-version --no-git --no-git-tag-version $(VERSION)
	echo $(VERSION) > VERSION

clean:
	rm -Rf tmp/
	rm -Rf build/
	rm -RF node_moudles/
	rm parameter*.json
