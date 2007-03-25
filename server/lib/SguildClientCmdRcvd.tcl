# $Id: SguildClientCmdRcvd.tcl,v 1.26 2007/03/25 05:21:17 bamm Exp $

#
# ClientCmdRcvd: Called when client sends commands.
#
proc ClientCmdRcvd { socketID } {
  global clientList validSockets GLOBAL_QRY_LIST REPORT_QRY_LIST
                                                                                                            
  if { [eof $socketID] || [catch {gets $socketID data}] } {
    # Socket closed
    close $socketID
    ClientExitClose $socketID
    LogMessage "Socket $socketID closed" 
  } else {
    InfoMessage "Client Command Received: $data"
    set origData $data
    set clientCmd [ctoken data " "]
    # Check to make the client validated itself
    if { $clientCmd != "ValidateUser" && $clientCmd != "PING" && $clientCmd != "VersionInfo" } {
      if { [lsearch -exact $validSockets $socketID] < 0 } {
        catch {SendSocket $socketID\
         "InfoMessage {Client does not appear to be logged in. Please exit and log back in.}"} tmpError
      return
      }
    }
    set data1 [string trimleft $data]
    # data1 will contain the list from index 1 on.
    set index1 [ctoken data " "]
    set data2 [string trimleft $data]
    # data2 now contains only indices 2 on, because ctoken chops tokens off
    set index2 [ctoken data " "]
    # data3 now contains indicies 3 on
    set data3 [string trimleft $data]
    set index3 [ctoken data " "]
    set index4 [ctoken data " "]
    switch -exact $clientCmd {
      DeleteEventID { $clientCmd $socketID $index1 $index2 }
      DeleteEventIDList { $clientCmd $socketID $data1 }
      EventHistoryRequest { $clientCmd $socketID $index1 $index2 $data3 }
      ExecDB { $clientCmd $socketID $data1 }
      GetCorrelatedEvents { $clientCmd $socketID $index1 $index2 }
      GetIcmpData { $clientCmd $socketID $index1 $index2 }
      GetIPData { $clientCmd $socketID $index1 $index2 }
      GetPayloadData { $clientCmd $socketID $index1 $index2 }
      GetPSData { $clientCmd $socketID $index1 $index2 $data3 }
      GetTcpData { $clientCmd $socketID $index1 $index2 }
      GetUdpData { $clientCmd $socketID $index1 $index2 }
      MonitorSensors { $clientCmd $socketID $data1 }
      QueryDB { $clientCmd $socketID $index1 $data2 }
      RuleRequest { $clientCmd $socketID $index1 $index2 $data3 }
      SendSensorList { $clientCmd $socketID }
      SendEscalatedEvents { $clientCmd $socketID }
      SendDBInfo { $clientCmd $socketID }
      ValidateUser { ValidateUser $socketID $index1 }
      PING { puts $socketID "PONG" }
      UserMessage { UserMsgRcvd $socketID $data1 }
      SendGlobalQryList { SendSocket $socketID "GlobalQryList $GLOBAL_QRY_LIST" }
      SendReportQryList { SendSocket $socketID "ReportQryList $REPORT_QRY_LIST" }
      ReportRequest { ReportBuilder $socketID $index1 $index2 $data3 }
      GetSancpFlagData { $clientCmd $socketID $index1 $index2 }
      XscriptRequest { eval $clientCmd $socketID $data1 }
      EtherealRequest { eval $clientCmd $socketID $data1 }
      AbortXscript { $clientCmd $socketID $index1 }
      LoadNessusReports { $clientCmd $socketID $index1 $index2 $data3 }
      GetOpenPorts { $clientCmd $socketID $index1 $index2 }	
      SendClientSensorStatusInfo { $clientCmd $socketID }
      GetAssetData { $clientCmd $socketID $index1 $index2 }
      VersionInfo { ClientVersionCheck $socketID $data1 }
      default { InfoMessage "Unrecognized command from $socketID: $origData" }
    }
  }
}

proc ClientExitClose { socketID } {
  global clientList  clientMonitorSockets validSockets socketInfo sensorUsers
  set userName [lindex $socketInfo($socketID) 2]
  if { [info exists clientList] } {
    set clientList [ldelete $clientList $socketID]
  }
  if { [info exists clientMonitorSockets] } {
    foreach sensorName [array names clientMonitorSockets] {
      set clientMonitorSockets($sensorName) [ldelete $clientMonitorSockets($sensorName) $socketID]
    }
  }
  if { [info exists validSockets] } {
    set validSockets [ldelete $validSockets $socketID]
  }
  if { [array exists sensorUsers] } {
    foreach sensorName [array names sensorUsers] {
      set sensorUsers($sensorName) [ldelete $sensorUsers($sensorName) $userName]
    }
  }
  if { [info exists socketInfo($socketID)] } {
    set tmpUserName [lindex $socketInfo($socketID) 2]
    unset socketInfo($socketID)
    SendSystemInfoMsg sguild "User $tmpUserName has disconnected."
  }
}

proc UserMsgRcvd { socketID userMsg } {
  global socketInfo clientList 
                                                                                                            
  set userMsg [lindex $userMsg 0]
                                                                                                            
  # Simple command stuff.
  # Who returns a list of connected users
  if { $userMsg == "who" } {
     foreach client $clientList { lappend usersList [lindex $socketInfo($client) 2] }
     SendSocket $socketID [list UserMessage sguild "Connected users: $usersList"]
  } elseif { $userMsg == "healthcheck" } { 
    #SensorAgentsHealthCheck 1
    SendSocket $socketID [list UserMessage sguild "Command healthcheck depreciated."]
  } else {
    foreach client $clientList {
      SendSocket $client [list UserMessage [lindex $socketInfo($socketID) 2] $userMsg]
    }
  }
}

proc GetCorrelatedEvents { socketID eid winName } {
  global correlatedEventArray eventIDArray
  if { [info exists eventIDArray] } {
    SendSocket $socketID\
     "InsertQueryResults $winName [eval FormatStdToQuery [lrange $eventIDArray($eid) 0 12]]"
  }
                                                                                                            
  if { [info exists correlatedEventArray($eid)] } {
    foreach row $correlatedEventArray($eid) {
      SendSocket $socketID "InsertQueryResults $winName [eval FormatStdToQuery [lrange $row 0 12]]"
    }
  }
}

proc FormatStdToQuery { status priority class sensor time sid cid msg sip dip proto sp dp } {
  return "[list $status $priority $sensor $time $sid $cid $msg $sip $dip $proto $sp $dp]"
}


proc SendDBInfo { socketID } {
  global tableNameList tableArray
  catch {SendSocket $socketID "TableNameList $tableNameList"} tmpError
  foreach tableName $tableNameList {
    catch {SendSocket $socketID "TableColumns $tableName $tableArray($tableName)"} tmpError
  }
}

#
# RuleRequest finds rule based on message. Should change this to
# use sig ids in the future.
#
proc RuleRequest { socketID event_id sensor message } {

    global RULESDIR
                                                                                                            
    set RULEFOUND 0
    set ruleDir $RULESDIR/$sensor

    # Check for an alert with no sid-msg.map (Snort Alert [#:#:#])
    if { [regexp {Snort Alert \[([0-9]+):([0-9]+):([0-9]+)\]} $message match gen_id rule_id rev] } {

        set search_string "sid:$rule_id"

    } else {

        set search_string "msg:*\"$message\""

    }
  

    if { [file exists $ruleDir] } {

        foreach ruleFile [glob -nocomplain $ruleDir/*.rules] {

            InfoMessage "Checking $ruleFile..."
            set ruleFileID [open $ruleFile r]
            set line 0

            while { [gets $ruleFileID data] >= 0 } {

                incr  line
                if { [string match "*$search_string*" $data] } {
                    set RULEFOUND 1
                    InfoMessage "Matching rule found in $ruleFile."
                    break
                }

            }

            close $ruleFileID
            if {$RULEFOUND} {break}

        }

    } else {
  
        set data "Could not find $ruleDir."

    }

    if {$RULEFOUND} {

        catch {SendSocket $socketID "InsertRuleData $data"} tmpError
        catch {SendSocket $socketID "InsertRuleData $ruleFile: Line $line"} tmpError

    } else {

        catch {SendSocket $socketID "InsertRuleData Unable to find matching rule in $ruleDir."} tmpError

    }

}

proc GetPSData { socketID timestamp srcIP MAX_PS_ROWS } {
  global DBNAME DBUSER DBPASS DBPORT DBHOST
  if { $MAX_PS_ROWS == 0 } {
    set query\
    "SELECT * FROM portscan WHERE timestamp > '$timestamp' AND src_ip='$srcIP'"
  } else {
    set query\
    "SELECT * FROM portscan WHERE timestamp > '$timestamp' AND src_ip='$srcIP' LIMIT $MAX_PS_ROWS"
  }
  InfoMessage "Getting PS data: $query"
  if {$DBPASS == ""} {
    set dbSocketID [mysqlconnect -host $DBHOST -db $DBNAME -user $DBUSER -port $DBPORT]
  } else {
    set dbSocketID [mysqlconnect -host $DBHOST -db $DBNAME -user $DBUSER -port $DBPORT -password $DBPASS]
  }
  foreach row [mysqlsel $dbSocketID "$query" -list] {
    catch {SendSocket $socketID "PSDataResults $row"} tmpError
  }
  mysqlclose $dbSocketID
  catch {SendSocket $socketID "PSDataResults DONE"} tmpError
}

proc EventHistoryRequest { socketID winName sid cid } {
  global DBNAME DBUSER DBPORT DBHOST DBPASS
  if { $DBPASS == "" } {
    set dbSocketID [mysqlconnect -host $DBHOST -db $DBNAME -user $DBUSER -port $DBPORT]
  } else {
    set dbSocketID [mysqlconnect -host $DBHOST -db $DBNAME -user $DBUSER -port $DBPORT -password $DBPASS]
  }
  set query "SELECT history.sid, history.cid, user_info.username, history.timestamp, history.status, status.description, history.comment FROM history, user_info, status WHERE history.uid=user_info.uid AND history.status=status.status_id AND history.sid=$sid and history.cid=$cid"
  if [catch {mysqlsel $dbSocketID "$query" -list} selResults] {
    catch {SendSocket $socketID "InfoMessage $selResults"} tmpError
  } else {
    foreach row $selResults {
      catch {SendSocket $socketID "InsertHistoryResults $winName $row"} tmpError
    }
  }
  mysqlclose $dbSocketID
  catch {SendSocket $socketID "InsertHistoryResults $winName done"} tmpError
}

proc GetSancpFlagData { socketID sensorID xid } {
  set query\
   "SELECT src_flags, dst_flags FROM sancp WHERE sancp.sid=$sensorID AND sancp.sancpid=$xid"
   set queryResults [FlatDBQuery $query]
   catch {SendSocket $socketID "InsertSancpFlags $queryResults"}
}
proc GetIPData { socketID sid cid } {
  set query\
   "SELECT INET_NTOA(src_ip), INET_NTOA(dst_ip), ip_ver, ip_hlen, ip_tos, ip_len, ip_id,\
    ip_flags, ip_off, ip_ttl, ip_csum\
   FROM event\
   WHERE sid=$sid and cid=$cid"
                                                                                                            
  set queryResults [FlatDBQuery $query]
  catch {SendSocket $socketID "InsertIPHdr $queryResults"} tmpError
}
proc GetTcpData { socketID sid cid } {
  set query\
   "SELECT tcp_seq, tcp_ack, tcp_off, tcp_res, tcp_flags, tcp_win, tcp_urp, tcp_csum\
   FROM tcphdr\
   WHERE sid=$sid and cid=$cid"
  set queryResults [FlatDBQuery $query]
  set portQuery [FlatDBQuery "SELECT src_port, dst_port FROM event WHERE sid=$sid AND cid=$cid"]
  catch {SendSocket $socketID "InsertTcpHdr $queryResults $portQuery"} tmpError
}
proc GetIcmpData { socketID sid cid } {
  set query\
   "SELECT event.icmp_type, event.icmp_code, icmphdr.icmp_csum, icmphdr.icmp_id, icmphdr.icmp_seq\
   FROM event, icmphdr\
   WHERE event.sid=icmphdr.sid AND event.cid=icmphdr.cid AND event.sid=$sid AND event.cid=$cid"
                                                                                                            
  set queryResults [FlatDBQuery $query]
                                                                                                            
  set query\
   "SELECT data_payload FROM data WHERE sid=$sid and cid=$cid"
                                                                                                            
  set plqueryResults [FlatDBQuery $query]
                                                                                                            
  catch {SendSocket $socketID "InsertIcmpHdr $queryResults $plqueryResults"} tmpError
}
proc GetPayloadData { socketID sid cid } {
  set query\
   "SELECT data_payload FROM data WHERE sid=$sid and cid=$cid"
                                                                                                            
  set queryResults [FlatDBQuery $query]
  catch {SendSocket $socketID "InsertPayloadData \{$queryResults\}"} tmpError
}
proc GetUdpData { socketID sid cid } {
  set query\
   "SELECT udp_len, udp_csum FROM udphdr WHERE sid=$sid and cid=$cid"
                                                                                                            
  set queryResults [FlatDBQuery $query]
  set portQuery [FlatDBQuery "SELECT src_port, dst_port FROM event WHERE sid=$sid AND cid=$cid"]
  catch {SendSocket $socketID "InsertUdpHdr $queryResults $portQuery"} tmpError
}

proc GetOpenPorts { socketID sid cid } {
    global DBNAME DBUSER DBPASS DBPORT DBHOST

    if {$DBPASS == ""} {
	set dbSocketID [mysqlconnect -host $DBHOST -db $DBNAME -user $DBUSER -port $DBPORT]
    } else {
	set dbSocketID [mysqlconnect -host $DBHOST -db $DBNAME -user $DBUSER -port $DBPORT -password $DBPASS]
    }

    set query\
	"SELECT unified_event_id FROM event WHERE sid=$sid and cid=$cid"
    set event_id [lindex [FlatDBQuery $query] 0]
    if { $event_id == "" } { 
	catch {SendSocket $socketID "InsertOpenPortsData DONE"} tmpError
	return
    }
    set query\
	"SELECT INET_NTOA(event.dst_ip), data.data_payload from event, data WHERE event.sid=data.sid AND event.cid=data.cid AND event.unified_event_ref=$event_id"
    foreach row [mysqlsel $dbSocketID "$query" -list] {
    catch {SendSocket $socketID "InsertOpenPortsData $row"} tmpError
    }
    mysqlclose $dbSocketID
    catch {SendSocket $socketID "InsertOpenPortsData DONE"} tmpError
}
#
# MonitorSensors: Sends current events to client. Adds client to clientList
#                 In the future sensorList will contain a list of sensors, for
#                 now the client gets everything.
#
proc MonitorSensors { socketID ClientSensorList } {

    global clientList clientMonitorSockets socketInfo sensorUsers sensorList
    global snortStatsArray
   

    set userName [lindex $socketInfo($socketID) 2]

    if {[lsearch -exact $clientList $socketID] < 0} { 
	LogMessage "$socketID added to clientList"
	lappend clientList $socketID
    }
    # Find this socketID in other sensors and delete it 
    foreach sensor $sensorList {
	if [info exists clientMonitorSockets($sensor)] {
            set clientMonitorSockets($sensor) [ldelete $clientMonitorSockets($sensor) $socketID]
	}
	if [info exists sensorUsers($sensor)] {
            set sensorUsers($sensor) [ldelete $sensorUsers($sensor) $userName]
	}
    }

    foreach sensorName $ClientSensorList {
	lappend clientMonitorSockets($sensorName) $socketID
	lappend sensorUsers($sensorName) $userName
    }
    SendSystemInfoMsg sguild "User [lindex $socketInfo($socketID) 2] is monitoring sensors: $ClientSensorList"
    SendCurrentEvents $socketID

    # Send the snort stats info here.
    if { [array exists snortStatsArray] && [array names snortStatsArray] != "" } {

        foreach sensor [array names snortStatsArray] {

            lappend tmpList [linsert $snortStatsArray($sensor) 1 $sensor]

        }

        catch { SendSocket $socketID [list NewSnortStats $tmpList] } tmpError

    }   

}
                                                                                                            
proc SendEscalatedEvents { socketID } {
  global escalateIDList escalateArray
  if [info exists escalateIDList] {
    foreach escalateID $escalateIDList {
      catch {SendSocket $socketID "InsertEscalatedEvent $escalateArray($escalateID)"} tmpError
    }
  }
}

#
# SendCurrentEvents: Sends newly connected clients the current event list
#
proc SendCurrentEvents { socketID } {
  global eventIDArray eventIDList clientMonitorSockets eventIDCountArray
  global sidNetNameMap
                                                                                                                       
  if { [info exists eventIDList] && [llength $eventIDList] > 0 } {
    foreach eventID $eventIDList {
      set sensorID [lindex [split $eventID .] 0]
      set netName $sidNetNameMap($sensorID)
      if { [info exists clientMonitorSockets($netName)] } {
        if { [lsearch -exact $clientMonitorSockets($netName) $socketID] >= 0} {
          InfoMessage "Sending client $socketID: InsertEvent [lrange $eventIDArray($eventID) 0 12]" 
          catch {\
           SendSocket $socketID "InsertEvent [lrange $eventIDArray($eventID) 0 12] $eventIDCountArray($eventID)"\
          } tmpError
        }
      }
    }
  }
}

proc LoadNessusReports { socketID filename table bytes} {
    global TMPDATADIR sguildWritePipe userIDArray
    InfoMessage "Receiving nessus file $filename."
    set NESSUS_OUTFILE $TMPDATADIR/$filename
    set outFileID [open $NESSUS_OUTFILE w]
    fconfigure $outFileID -translation binary
    fconfigure $socketID -translation binary
    fcopy $socketID $outFileID -size $bytes
    close $outFileID
    fconfigure $socketID -encoding utf-8 -translation {auto crlf}
    InfoMessage "Loading $filename into DB."
    if { $table == "main" } {
	set NESSUS_OUTFILE2 "$TMPDATADIR/tmp${filename}"
	set outFileID [open $NESSUS_OUTFILE2 w]
	set uid $userIDArray($socketID)
	for_file line $NESSUS_OUTFILE {
	    if {$line != ""} {
		regsub {^\|\|} $line "||${uid}|" line
		puts $outFileID $line
	    }
	}
	close $outFileID
	file delete $NESSUS_OUTFILE
	file copy -force $NESSUS_OUTFILE2 $NESSUS_OUTFILE
	
        set cmd "LOAD DATA LOCAL INFILE '$NESSUS_OUTFILE' INTO TABLE nessus FIELDS TERMINATED\
                BY '|' LINES TERMINATED BY '||' STARTING BY '||'"
    } else {
        set cmd "LOAD DATA LOCAL INFILE '$NESSUS_OUTFILE' INTO TABLE nessus_data FIELDS TERMINATED\
                 BY '|' LINES TERMINATED BY '||'STARTING BY '||'"
    }

    # The loader child proc does the LOAD for us.
    puts $sguildWritePipe [list LoadNessusData $NESSUS_OUTFILE $cmd]
    flush $sguildWritePipe
    puts $socketID "InfoMessage Nessus Data sent to loader.  Check server debug for any loading errors."

}


