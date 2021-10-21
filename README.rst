===============
Account Service
===============

----------------------------------
FlagAutouseCidashNotificationTopic
----------------------------------
Wenn diese Flag auf true gesetzt wird, muss bereits vorher ein
aderer Stack existieren welcher die ciDashArn Variable "exportiert"
Siehe: https://github.com/eieste/cidash
(Im normalfall wurde die subscribe.yml deployed)

--------------------
FeatureFlagSns2Slack
--------------------
Fügt eine Lambda Funktion zum sns Topic hinzu
Diese Funktion hängt von CfnNotificationTopicArn ab


---------------------------
FeatureFlagMysqlLambdaLayer
---------------------------
Erstellt einen Python basierten Lambda Layer für MySQL bereit
Der layer wird für zwangsweiße benötigt wenn FeatureFlagRah true ist


---------------------------
FeatureFlagPostgresLambdaLayer
---------------------------
Erstellt einen Python basierten Lambda Layer für Postgres bereit
Der layer wird für zwangsweiße benötigt wenn FeatureFlagRah true ist

---------------------
FeatureFlagCloudTrail
---------------------

Enables / Disable Cloudtrail for current Account

--------------
FeatureFlagRah
--------------

Ermöglicht das erstellen von nutzern und Datenbanken mit Cloudformation in einer RDS datenbank


-------------------------
FeatureFlagCostCredential
-------------------------

Erstellt einen IAM user welcher kosten erfassen kann

-------------------------
FeatureFlagNukeCredential
-------------------------

Erstellt einen IAM user welcher verwendet werden kann um accounts zu nuken


for aws config
==============


Conformance Pack Samples:

https://docs.aws.amazon.com/config/latest/developerguide/conformancepack-sample-templates.html
