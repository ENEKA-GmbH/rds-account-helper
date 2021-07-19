

#!/usr/bin/python3.6
import urllib3
import json
import logging
import os
import secrets

SLACK_URL = "https://hooks.slack.com/services/"

http = urllib3.PoolManager()

log = logging.getLogger(__name__)

def get_channel_config(data):
    dat = {}
    segments = data.split(";")
    for seg in segments:
        info = seg.split("=")
        dat[info[0]] = {
                "channel_name": info[1].split(":")[0],
                "chanenl_id": info[1].split(":")[1],
                }
    return dat

def lambda_handler(event, context):
    evt = event.get("Records")[0]
    setting = secrets.get_secret(os.environ.get("SecretName"), os.environ.get("AwsRegion"))
    url = "https://hooks.slack.com/services/{slack_token}".format(slack_token=setting.get("slack_token"))
    msg = False
    channel_config = get_channel_config(setting.get("slack_channel"))
    if "CloudFormation" in evt["Sns"].get("Subject"):
        log.info("CloudFormation Topic Detected")
        message = evt['Sns']['Message'].strip()
        cfn_msg = {k:v.strip('\'').strip("\"") for k,v in (x.split('=') for x in message.split('\n')) }
        log.info("Check if Status {} is allowed".format(cfn_msg.get("ResourceStatus")))        
        if cfn_msg.get("ResourceStatus") in setting.get("allowed_cfn_states").split(";"):
            msg = {
                "channel": channel_config["cfn"]["channel_name"],
                "username": setting.get("slack_username"),
                "mrkdwn": True,
                "text": "*{}*\n {} \n {}".format(cfn_msg.get("ResourceStatus"), cfn_msg.get("ResourceStatusReason"), cfn_msg.get("StackId"))
            }
    print(cfn_msg.get("ResourceStatus"))
    print(evt["Sns"].get("Subject"))
    if msg:
        encoded_msg = json.dumps(msg).encode('utf-8')
        resp = http.request('POST',url, body=encoded_msg)
        log.debug({
            "message": evt['Sns']['Message'], 
            "status_code": resp.status, 
            "response": resp.data
        })


