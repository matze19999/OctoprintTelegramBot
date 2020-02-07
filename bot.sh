#!/bin/bash
clear
# Variablen setzen
BOTTOKEN='' # from telegram
SLEEPTIME='0.7' # how often should I check for new telegram messages?
USERIDS='' # space seperated
DNDFROM="17" #clock
DNDTO="5" #clock
HOSTNAME='octoprint'
PORT='80' # port from octoprint
APIKEY='' # from octoprint


# Test ob alle Pakete installiert sind
which bc curl apt jq wget sed > /dev/null
if [[ $? == "1" ]];then
        apt update && apt install curl apt jq wget sed -y
        exit 0
fi

foldernames=""

# Deaktiviert Case Matching
shopt -s nocasematch

# Get the latest telegram message sent to the bot
function getlatestmessage {

    API=`wget --no-cache --no-cookies "https://api.telegram.org/bot$BOTTOKEN/getUpdates" --no-check-certificate -q -O -`
    LATESTMESSAGE=`echo "$API" | jq -r ".result[-1].message.text"`
    LATESTUSERNAME=`echo "$API" | jq -r ".result[-1].message.chat.username"`
    CHATID_LASTMESSAGE=`echo "$API" | jq -r ".result[-1].message.chat.id"`
    FILESENT=`echo "$API" | jq -r ".result[-1].message.document.file_name"`
    FILEID=`echo "$API" | jq -r ".result[-1].message.document.file_id"`
    FILEPATH=`wget --no-cache --no-cookies "https://api.telegram.org/bot$BOTTOKEN/getFile?file_id=$FILEID" --no-check-certificate -q -O - | jq .result.file_path | sed -e 's/"//g'`
    FILEURL="https://api.telegram.org/file/bot$BOTTOKEN/$FILEPATH"

}

generate_post_data()
{
  cat <<EOF
{"keyboard":$filearray}
EOF
}

function ReplyKeyboardMarkup {
        curl -s -X POST "https://api.telegram.org/bot$BOTTOKEN/sendMessage" --header 'content-type: multipart/form-data' --form chat_id=$CHATID_LASTMESSAGE --form "text=$1" --form "one_time_keyboard=true" --form reply_markup=$(generate_post_data)
        openkeyboard="$CHATID_LASTMESSAGE"
}


# Sendet eine Telegram Nachricht
function sendmessage {
        if [[ "$openkeyboard" == "$CHATID_LASTMESSAGE" ]];then
                curl -s -X POST "https://api.telegram.org/bot$BOTTOKEN/sendMessage" --form chat_id=$CHATID_LASTMESSAGE --form "parse_mode=HTML" --form "text=schließe Tastatur..." --header 'content-type: multipart/form-data' --form reply_markup='{"remove_keyboard":'true'}'
                openkeyboard = "0"
        fi
        curl -s -X POST "https://api.telegram.org/bot$BOTTOKEN/sendMessage" -d chat_id=$CHATID_LASTMESSAGE -d "parse_mode=HTML" -d "text=$1"

}

function progress-bar() {
    local w=60 p=$1;  shift
    printf -v dots "%*s" "$(( $p*$w/100 ))" ""; dots=${dots// /.};
    printf "\r\e|%-*s| %3d %% %s" "$w" "$dots" "$p" "$*"; 
}

connecttoprinter() {

        runs=5
        while [ "$runs" -ne 0 ]
        do
                connection=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/connection" | jq .current.state | sed -e 's/"//g'`

                if [[ "$connection" == "Closed" ]];then
                        curl -s -H "X-Api-Key: $APIKEY" -H Accept:application/json -H Content-type:application/json -X POST -d '{"command":"connect","port":"/dev/ttyUSB0","baudrate":250000,"autoconnect":"true"}' "http://$HOSTNAME:$PORT/api/connection"
                        #echo "runs: $runs"
                        let runs--
                elif [[ "$connection" != "Closed" ]];then
                        sendmessage "Verbindung zum Drucker aufgebaut!"
                        break
                fi
       done
        if [[ "$runs" == '0' ]];then
                sendmessage "Es konnte keine Verbindung zum Drucker aufgebaut werden"
        fi

}


function getprintdata {

                connection=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/connection" | jq .current.state | sed -e 's/"//g'`

                if [[ "$connection" == "Closed" ]];then
                        connecttoprinter
                fi

                state=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/printer" | jq .state.text | sed -e 's/"//g'`

                case "$state" in
                        Printing)       state="Drucken 🖨" ;;
                        Operational)    state="Betriebsbereit 🚀" ;;
                esac

                extruder_actual=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/printer" | jq .temperature.tool0.actual`
                extruder_target=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/printer" | jq .temperature.tool0.actual`

                bed_actual=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/printer" | jq .temperature.bed.actual`
                bed_target=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/printer" | jq .temperature.bed.target`

                filename=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/job" | jq .job.file.name | sed -e 's/"//g'`

                progress=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/job" | jq .progress.completion | cut -c 1-2`

                printTimeLeftSeconds=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/job" | jq .progress.printTimeLeft | cut -c 1-5`
                printTimeLeft=`date -d@"$printTimeLeftSeconds" -u +%H:%M:%S`

                currentLayer=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/plugin/DisplayLayerProgress/values" | jq .layer.current | sed -e 's/"//g'`
                totalLayer=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/plugin/DisplayLayerProgress/values" | jq .layer.total | sed -e 's/"//g'`

                fanSpeed=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/plugin/DisplayLayerProgress/values" | jq .fanSpeed | sed -e 's/"//g'`

                printDoneTime_seconds=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/job" | jq .progress.printTime`
                printDoneTime=`date -d@"$printDoneTime_seconds" -u +%H:%M:%S`

                localFiles=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/files/local" | jq ".files | sort_by(.date) | reverse | .[].name"`
                nofolder=true
                filearray=""
                for file in $localFiles;do
                        if [[ "$file" == *".gcode"* ]];then
                                filearraypiece="["$file"],"
                                filearray="$filearray$filearraypiece"
                        fi
                        if [[ "$file" != *".gcode"* ]];then
                                foldernames="$foldernames $file"
                                foldernames=`echo $foldernames | sed -e 's/"//g'`
                                file=`echo $file | sed -e 's/"//g'`
                                echo "Ordner ist $file"
                                nofolder=false
                                fileinfolder=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/files/local/$file" | jq ".children | sort_by(.date) | reverse | .[].name"`
                                for file in $fileinfolder;do
                                        filearraypiece="["$file"],"
                                        filearray="$filearray$filearraypiece"
                                done
                        fi
                done
                filearray=""[$filearray]""
                filearray=`echo $filearray | rev | cut -c3- | rev`
                filearray="$filearray,["\""/cancel"\""]"
                filearray="$filearray]"
                echo $filearray

                if [[ "$printDoneTime_hours" == "" ]];then
                        printDoneTime_hours="0h"
                fi
                printDoneTime="$printDoneTime_hours"h" $printDoneTime_minutes"m

                if [[ "$extruder_actual" > 150 ]];then
                        heatemoji=🔥
                else
                        heatemoji=❄️
                fi
}

echo "Warte auf Nachrichten..."

# Ruft Funktion getlatestmessage auf
getlatestmessage

donesend=1

# Checkt auf neue Nachrichten
while true;
do
        HOUR=`date +%H`
        OLDMESSAGEDATE=`echo "$API" | jq -r ".result[-1].message.date"`
        getlatestmessage
        MESSAGEDATE=`echo "$API" | jq -r ".result[-1].message.date"`
        progress=`curl -s -k -H "X-Api-Key: $APIKEY" "http://$HOSTNAME:$PORT/api/job" | jq .progress.completion | cut -c 1-3`

        if [[ "$progress" == *"100"* && "$donesend" == "0" ]];then
                getprintdata
                sendmessage "Druck $filename fertig!"
                donesend=1
        elif [[ "$progress" != *"100"* ]];then
                donesend=0
        fi

        chat_id_ok=false
        for i in $USERIDS; do
                if [ "$i" == "$CHATID_LASTMESSAGE" ]; then
                        chat_id_ok=true
                        break
                fi
        done

        if [[ "$OLDMESSAGEDATE" != "$MESSAGEDATE" ]] && [[ "$chat_id_ok" == 'true' ]] && (( $(echo "$HOUR < $DNDFROM" | bc -l) )) && (( $(echo "$HOUR > $DNDTO" | bc -l) ));then
                curl -s -X POST "https://api.telegram.org/bot$BOTTOKEN/sendChatAction" -d "chat_id=$CHATID_LASTMESSAGE" -d "action=typing"
                echo "Letzte Nachricht: $LATESTMESSAGE von $LATESTUSERNAME mit der ID $CHATID_LASTMESSAGE"
                getprintdata

                if [[ "$LATESTMESSAGE" == "/status" ]];then
                                message="Aktueller Status: $state"
                                if [[ "$state" == 'Drucken 🖨' ]];then
                                        progressbar=`progress-bar $progress`
                                        message="$message%0A%0AExtruder: $extruder_actual°C $heatemoji%0ABett: $bed_actual°C $heatemoji%0A%0ADateiname: $filename%0A%0AVerbleibend: $printTimeLeft%0A%0ALayer: $currentLayer/$totalLayer%0A%0ALüfter: $fanSpeed 💨%0A%0AFortschritt:%0A$progressbar"
                                        sendmessage "$message"
                                elif [[ "$state" == 'Betriebsbereit 🚀' ]];then
                                        message="$message%0A%0ALetzer Druck: $filename"
                                        sendmessage "$message"
                                fi

                elif [[ "$FILESENT" == *".gcode" ]];then
                        filefound=false
                        for file in $localFiles; do
                                if [ "$file" == "$FILESENT" ]; then
                                        filefound=true
                                        break
                                fi
                        done
                        if [[ "$filefound" == 'true' ]];then
                                sendmessage "Datei bereits vorhanden!"
                        else
                                wget -q --no-cache --no-cookies "$FILEURL" -O "/tmp/$FILESENT"
                                curl -k -H "X-Api-Key: $APIKEY" -F "select=true" -F "print=false" -F "file=@/tmp/$FILESENT" "http://$HOSTNAME:$PORT/api/files/local"
                                sendmessage "Datei wurde in OctoPrint hochgeladen!"
                                rm -rf "/tmp/$FILESENT"
                        fi
                elif [[ "$LATESTMESSAGE" == *".gcode" ]];then
                        if [[ "$state" == 'Drucken 🖨' ]];then
                                sendmessage "Druckvorgang, Neustart abgelehnt!"
                        else
                                curl -s -H "X-Api-Key: $APIKEY" -H Accept:application/json -H Content-type:application/json -X POST -d '{"command":"select","print":"true"}' "http://$HOSTNAME:$PORT/api/files/local/$LATESTMESSAGE"
                                for folder in $foldernames;do
                                        folder="$folder/"
                                        curl -s -H "X-Api-Key: $APIKEY" -H Accept:application/json -H Content-type:application/json -X POST -d '{"command":"select","print":"true"}' "http://$HOSTNAME:$PORT/api/files/local/$folder$LATESTMESSAGE"
                                done
                                sendmessage "Druckvorgang wird gestartet! /status senden zum überwachen"
                        fi

                elif [[ "$LATESTMESSAGE" == "/cancelprint" ]];then
                        if [[ "$state" == 'Drucken 🖨' ]];then
                                curl -s -H "X-Api-Key: $APIKEY" -H Accept:application/json -H Content-type:application/json -X POST -d '{"command":"cancel"}' "http://$HOSTNAME:$PORT/api/job"
                                sendmessage "Druck wurde abgebrochen!"
                        else
                                sendmessage "Es wird gerade nichts gedruckt!"
                        fi
                                

                elif [[ "$LATESTMESSAGE" == "/pauseprint" ]];then
                        if [[ "$state" == 'Drucken 🖨' ]];then
                                curl -s -H "X-Api-Key: $APIKEY" -H Accept:application/json -H Content-type:application/json -X POST -d '{"command":"pause"}' -d '{"action":"toggle"}' "http://$HOSTNAME:$PORT/api/job"
                                sendmessage "Druck wurde pausiert. Zum fortsetzen Kommando /pauseprint erneut senden."
                        fi        

                elif [[ "$LATESTMESSAGE" == "/restartoctoprint" ]];then
                        if [[ "$state" == 'Drucken 🖨' ]];then
                                sendmessage "Druckvorgang, Neustart abgelehnt!"
                        else
                                 sendmessage "OctoPrint wird neu gestartet!"
                                service octoprint restart
                        fi

                elif [[ "$LATESTMESSAGE" == "/print" ]];then
                        if [[ "$state" != 'Drucken 🖨' ]];then
                                ReplyKeyboardMarkup "Welche Datei willst du drucken?"
                        else
                                sendmessage "Druck bereits in Arbeit!"
                        fi

                elif [[ "$LATESTMESSAGE" == "/cancel" ]];then
                        curl -s -X POST "https://api.telegram.org/bot$BOTTOKEN/sendMessage" --form chat_id=$CHATID_LASTMESSAGE --form "parse_mode=HTML" --form "text=schließe Tastatur..." --header 'content-type: multipart/form-data' --form reply_markup='{"remove_keyboard":'true'}'
                        openkeyboard=0

                elif [[ "$LATESTMESSAGE" == "/reboot" ]];then
                        if [[ "$state" == 'Drucken 🖨' ]];then
                                sendmessage "Druckvorgang, Neustart abgelehnt!"
                        else
                                sendmessage "Wird neu gestartet..."
                                reboot
                        fi      


                elif [[ "$LATESTMESSAGE" == "/start" ]];then
                                sendmessage "Herlich Willkommen beim OctoPrint 🐙 Bot.%0ABitte wähle eines der Commands aus um mit mir zu kommunizieren 🗨"

                # Wenn keine passende Nachricht erkannt wurde
                else
                        sendmessage "Ich verstehe kein Wort... 🤷🏼‍♂️"
                fi
        fi

sleep $SLEEPTIME
done

exit 0
