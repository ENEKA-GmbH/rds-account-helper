import cfnresponse
from datetime import date, timedelta
import os, json
import pymysql
import boto3
import botocore
import random
import string
import logging

log = logging.getLogger()
log.setLevel(logging.DEBUG)


class Secret:

    def __init__(self, source, target):
        self.source = source
        self.target = target

    @staticmethod
    def getSecret(secret_arn):
        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=session.region_name
        )

        try:
            log.info("Try to load secret from SecretsManager for Arn: {}".format(secret_arn))
            get_secret_value_response = client.get_secret_value(SecretId=secret_arn)
        except Exception as e:
            log.exception(e)
            raise e
        else:
            if 'SecretString' in get_secret_value_response:
                secret = get_secret_value_response['SecretString']
                return json.loads(secret)
            raise ValueError("Cant handle Binary secrets")

    @staticmethod
    def updateSecret(secret_arn, altered_secret):
        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=session.region_name
        )

        try:
            log.info("Try to update secret in Arn: {}".format(secret_arn))
            client.update_secret(
                SecretId=secret_arn,
                SecretString=json.dumps(altered_secret)
            )
        except Exception as e:
            log.error(e)
            raise e


class Helper:

    @staticmethod
    def get_random_string(length, simple=False):
        log.debug("Create random string with parameters: length={}; simple={}".format(length, simple))
        letters = string.ascii_lowercase

        if not simple:
            letters += string.digits + string.punctation

        result_str = ''.join(random.choice(letters) for i in range(length))
        return result_str

    @staticmethod
    def generateMissingCredential(username, password, database):
        if not username or username == "":
            username = "u{}".format(Helper.get_random_string(8, simple=True))

        if not password or password == "":
            password = "p{}".format(Helper.get_random_string(20))

        if not database or database == "":
            database = "d{}".format(Helper.get_random_string(8, simple=True))
        return username, password, database

def openConnection(host, username, password):

    conn = None
    trys = 0
    while trys <= 5 and conn is None:
        try:
            log.info("Try to open rds Connection")
            if conn is None:
                conn = pymysql.connect(host=host, user=username, password=password, connect_timeout=10, cursorclass=pymysql.cursors.DictCursor)
                log.info("Connection established")
                return conn
        except pymysql.err.OperationalError:
            log.info("Connection failed. Try again {}".format(trys))
        trys = trys + 1

    return conn


def handler(event, context, **kwargs):
    log.debug("Incomming event: {}".format(json.dumps(event)))
    properties = event["ResourceProperties"]
    secret = Secret(properties.get("SourceSecretArn", False), properties.get("TargetSecretArn", False))

    responseData = {}
    conn = None
    try:
        raw_source_secret = Secret.getSecret(secret.source)

        conn = openConnection(raw_source_secret.get("host"), raw_source_secret.get("username"), raw_source_secret.get("password"))

        if conn is None:
            cfnresponse.send(event, context, cfnresponse.FAILED, responseData)
            raise pymysql.err.OperationalError("Cant connect to mysql")

        if event.get("RequestType") == "Create" or event.get("RequestType") == "Update":
            log.info("Create DB-Credentials")
            try:
                create_process(conn, secret)
                cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)
                return
            except Exception as e:
                log.exception(e)
                cfnresponse.send(event, context, cfnresponse.FAILED, responseData)
                return
        if event.get("RequestType") == "Delete":
            log.info("Delete DB-Credentials")
            try:
                delete_process(conn, secret)
                cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData)
                return
            except Exception as e:
                log.exception(e)
                cfnresponse.send(event, context, cfnresponse.FAILED, responseData)
                return
    except Exception as e:
        log.exception(e)
        log.error(e)
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception as e:
                log.exception(e)
    cfnresponse.send(event, context, cfnresponse.FAILED, responseData)

def delete_process(conn, secret):
    raw_secret = Secret.getSecret(secret.target)

    username, database = raw_secret.get("username", False), raw_secret.get("database", False)
    with conn.cursor() as cur:

        log.info("Delete Database")
        cur.execute('DROP DATABASE IF EXISTS `{}`'.format(database))
        result_set = cur.fetchall()
        log.debug("DB-Drop Result: {}".format(result_set))

        log.info("Delete User")
        cur.execute('DROP USER %s@"%%"', username)
        result_set = cur.fetchall()
        log.debug("DROP USer Result: {}".format(result_set))

def create_process(conn, secret):
    raw_secret = Secret.getSecret(secret.target)

    username, password, database = Helper.generateMissingCredential(raw_secret.get("username", False), raw_secret.get("password", False), raw_secret.get("database", False))
    with conn.cursor() as cur:

        log.info("Create new Database")
        cur.execute('CREATE DATABASE IF NOT EXISTS `{}`'.format(database))
        result_set = cur.fetchall()
        log.debug("DB-Create Result: {}".format(result_set))

        log.info("Create a new User")
        cur.execute('CREATE USER %s@"%%" IDENTIFIED BY %s', (username, password))
        result_set = cur.fetchall()
        log.debug("User-Create Result: {}".format(result_set))

        log.info("Grant Permission")
        cur.execute('GRANT ALL PRIVILEGES ON `{}`.* TO %s@"%%"'.format(database), username)
        result_set = cur.fetchall()
        log.debug("Grand User Result: {}".format(result_set))

        log.debug("Database Name: {}".format(database))
        log.debug("User Name: {}".format(username))

    raw_secret.update({
        "username": username,
        "password": password,
        "database": database
    })

    Secret.updateSecret(secret.target, raw_secret)
