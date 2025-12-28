## Step 1: Create the Trigger Logic
In Zabbix, a trigger is just a condition. Let's create one that fires when a Cisco "Link Down" trap is received.

Go to Data collection > Hosts.

Click on Triggers next to your Cisco host.

Click Create trigger (top right).

Name: Cisco Interface Link Down on {HOST.NAME}

Severity: High (Red).

Expression: Click Add and use these settings:

Item: Select your host, then select SNMP traps (fallback).

Function: find() (This looks for a string).

V (Pattern): Link Down (Or whatever text your switch sends).

Result: any (Find any match).

The final code should look like this: find(/YourHostName/snmptraps.fallback,,"like","Link Down")=1

## Step 2: Ensure the Alert Automatically Clears
If you don't set a "Recovery Expression," the alert will stay red forever.

In the same Trigger window, look for OK event generation.

Select Recovery expression.

Recovery expression: find(/YourHostName/snmptraps.fallback,,"like","Link Up")=1 (Now, when you send a "Link Up" trap, the dashboard turns green again!)

## Step 3: Test the Alert with your Script
Once your deployment is back up and you've added the trigger in the Web UI, use your test-network-trap.bash to simulate a failure.

To Trigger the Red Alert:

Bash

./test-network-trap.bash "Interface GigabitEthernet0/1, changed state to Link Down"
To Clear the Alert (Green):

Bash

./test-network-trap.bash "Interface GigabitEthernet0/1, changed state to Link Up"

## Step 4: The Dashboard Action
Go to Monitoring > Problems.

When you send the "Link Down" trap, a new entry will appear in BOLD RED.
