DEBUG=0
#set -x

createBasicBugReportFile()
# $1 = filePath
# $2 = prefix
# $3 = tmpBugreportPath
# $4 = $descriptionOfCommand
# $5 = $commandsToExecute
{
    local tmpFilePath=$1
    local tmpPrefix=$2
    local tmpDirPath=$3

    if [ "$(uname)" = "SunOS" ]; then
        echo "Bug reporting not implemented yet. Ask Christian to do that if needed."
    else
        echo "Creating bug reporting temp directory: " $tmpDirPath
        if [ ! -d "$tmpDirPath" ]; then
            mkdir -p  "$tmpDirPath"
        fi

        (
        IFS=';'
        echo "Table of Content"
        echo "------------------------------------------"
        j=0
        for commandDesc in $descriptionOfCommand; do
            j=$((j+1))
            echo "$j. $commandDesc"
        done
        echo "----------endTableContent-----------------"
        echo ""

        unset IFS

        numberOfCommandDescriptions=$(echo $descriptionOfCommand | tr ';' '\n' | wc -l | bc)
        numberOfCommands=$(echo $commandsToExecute | tr ';' '\n' |wc -l | bc)

        if [ $numberOfCommandDescriptions !=  $numberOfCommands ]; then
            echo "Number of command descriptions ($numberOfCommandDescriptions) dissimilar to number of of commands ($numberOfCommands)."
        fi

        i=0
        numberOfCommands=$(expr "$numberOfCommands" - 1)

        while [[ $i < $numberOfCommands ]]
        do
            i=$((i+1))
            head1=$(echo $descriptionOfCommand | cut -d ';' -f $i)
            head2=$(echo $commandsToExecute | cut -d ';' -f $i)
            echo $i. $head1
            echo "----------------------"
            echo "$head2"
            $head2 2>&1
            echo
        done

        ) > "$tmpFilePath"
        unset IFS
    fi

}

writeFileToBugReport() # $1 = fileToAddPath $2 = bugReportFilePath   $3 = headline   $4 = index
{
    local fileToAddPath=$1
    local bugReportFilePath=$2
    local headline=$3
    local index=$4

    (echo $index. $headline
    echo "------------------------------"
    echo ""
    cat $fileToAddPath
    echo "") >>  $bugReportFilePath;
}

addEntryToTableOfContent() # $1 = $tmpReportfile $2 = $index $3 = $pieceOfInfo
{
    sed -ie '/endTableContent/ i\
    \'$2'. '$3' file
    ' $1
}

addFileToBugReport() # $1 = fileURI $2 = tmpReportfile $4 = index
{
    local pieceOfInfo=$1
    local tmpReportfile=$2
    local index=$4

    if [ $DEBUG == 1 ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "Function: addFileToBugReport"
        echo "PieceOfInfo: $pieceOfInfo"
        echo "TmpReportFile: $tmpReportfile"
        echo "Index: $index\n"
    fi

    echo "Include $pieceOfInfo y/n:"
    read yesOrNo
    # This needs to go into a function later
    while ! [ "$yesOrNo" = "y" ] && ! [ "$yesOrNo" = "n" ]; do
        echo "2 Please enter y for yes or n for no:"
        echo "You entered:" $yesOrNo
        read yesOrNo
    done
    if [[ $yesOrNo == "y" ]]; then
        writeFileToBugReport $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
        addEntryToTableOfContent $tmpReportfile $index $pieceOfInfo
        printp "\n File added: $pieceOfInfo \n"
    else
        printp "\n Chosen not to add $pieceOfInfo. \n"
    fi
}

addAllFilesInDirectory() # $1 = directory
{
    allFilesInDirectory=$(ls $item)
    for itemInDir in $allFilesInDirectory; do
        if [ -d $itemInDir ]; then
            addItemToBugReport $itemInDir $tmpReportfile $index
        else
            writeFileToBugReport $item/$itemInDir $tmpReportfile "$item/$itemInDir file" $index
            addEntryToTableOfContent $tmpReportfile $index $item/$itemInDir
            printp "\n File added: $item/$itemInDir \n"
        fi
    done
}

addItemToBugReport() # $1 = directory  $2 = $tmpReportfile $3 = content header $4 = index
{
    local item=$1
    local tmpReportfile=$2
    local index=$4

    if [ $DEBUG == 1 ]; then
        echo "************************************"
        echo "Function: addItemToBugReport"
        echo "Item: $item"
        echo "TmpReportFile: $tmpReportfile"
        echo "Index: $index\n"
    fi

    # refine logic here as there can be files coming as pieceOfInfo, this should not be

    if [ -d $item ]; then
        if [ $DEBUG == 1 ]; then
            echo "Adding directory: $item"
        fi
        echo "Include entire directory $item y/n:"
        read yesOrNo
        # This needs to go into a function later
        while ! [ "$yesOrNo" = "y" ] && ! [ "$yesOrNo" = "n" ]; do
            echo "2 Please enter y for yes or n for no:"
            echo "You entered:" $yesOrNo
            read yesOrNo
        done
        if [[ $yesOrNo == "y" ]]; then
            addAllFilesInDirectory $item $tmpReportfile $index
        else
            local itemsInDir=$(ls $item)
            for itemInDir in $itemsInDir; do
                addItemToBugReport $item/$itemInDir $tmpReportfile $index
            done
        fi
    else
        if [ $DEBUG == 1 ]; then
                echo "Adding file: $item"
        fi
        addFileToBugReport $item $tmpReportfile $index
        index=$(($index + 1))
    fi
    echo "$index"
}

checkForYesOrNo() # yesOrNo = $1
{
    echo "Not implemented"
}

sendBugReportMail()
# $1 = sender mail address
# $2 = destination mail address
# $3 = short description of problem
# $4 = long description of problem
# $5 = bug report file OR URL
# $6 = tmpDirPath
{
    local tmpDirPath=$6
    local tmpMailrc=$MAILRC
    local combinedFileName=combined.txt
    local fileToSendViaMail="$tmpDirPath/$combinedFileName"
    local smtpServer=$(getProperty dcache.bugreporting.smtp)

    (echo "Subject: $3 \n"
    echo "------------------------------------------"
    echo "Long description of problem"
    echo "------------------------------------------"
    echo "$4"
    echo "------------------------------------------"
    echo "\n"
    ) > "$fileToSendViaMail"
    if [ -f  $5 ]; then
        echo "$5" >> "$fileToSendViaMail"
    else
        (echo "------------------------------------------"
        echo "Bugreport file URL on dCache SE: $5       "
        echo "------------------------------------------"
        echo "\n"
        ) >> "$fileToSendViaMail"
    fi

    which telnet > /dev/null
    telnetPresent=$?
    which mailx  > /dev/null
    mailxPresent=$?
    which sendmail > /dev/null
    sendmailPresent=$?

    printp "\nPlease enter the number in brackets to use one of these clients to send your mail:"
    if [ $telnetPresent -eq 0 ]; then
        printp "\ntelnet(1) - you need to have dcache.bugreporting.smtp property set to a reachable SMTP server.
        Also uuencode needs to be present on the machine."
    fi
    if [ $mailxPresent -eq 0 ]; then
        printp "\nmailx(2) - you need to have your local mail client configured"
    fi
    if [ $sendmailPresent -eq 0 ]; then
        printp "\nsendmail(3) - you need to have your local mail client configured and uuencode installed."
    fi
    echo "\nChoice:"
    read mailClientChoice

    if [ $mailClientChoice = 3 ]; then
        sendmail $2 <  $fileToSendViaMail
    else if [ $mailClientChoice = 2 ]; then
        tmpMailrc=$MAILRC
        from=$1 smtp=$smtpServer \
                  mailx -n -s "$3" \
                  $2 < $fileToSendViaMail
        MAILRC=$tmpMailrc

    else if [ $mailClientChoice = 1 ]; then
        count=1
        while [ $count = 1 ]
        do
            ( echo open $smtpServer 25
              sleep 12
              echo "helo desy.de"
              echo "MAIL From: $1"
              echo "RCPT To:<$2>"
              echo "DATA"
              echo "To: <$2>"
              echo "From: $1 "
              echo "Subject: $3"
              echo "MIME-Version: 1.0"
              echo 'Content-Type: multipart/mixed; boundary="-q1w2e3r4t5"'
              echo
              echo '---q1w2e3r4t5'
              echo 'Content-Type: application; name="'$(basename $fileToSendViaMail)'"'
              echo "Content-Transfer-Encoding: base64"
              echo 'Content-Disposition: attachment; filename="'$(basename $fileToSendViaMail)'"'
              uuencode -m $fileToSendViaMail $(basename $fileToSendViaMail)
              echo '---q1w2e3r4t5--'
              echo "."
              echo "quit") | telnet
              count=2
              echo "Telnet done."
        done
        rm -rf "$tmpDirPath"/*
        fi
        fi
    fi
}

processBugReport()
{
    supportEmail=$(getProperty dcache.bugreporting.supporter.email)
    prefix=$(getProperty dcache.bugreporting.prefix)
    descriptionOfCommand=$(getProperty dcache.bugreporting.commands.description)
    commandsToExecute=$(getProperty dcache.bugreporting.commands)

    files=$(getProperty dcache.bugreporting.paths)
    tmpReportPath=/tmp/dcache-bugreport
    tmpReportfile=$tmpReportPath/bugReportFile.tmp
    FQSN="$(getProperty dcache.bugreporting.se.name):$(getProperty dcache.bugreporting.se.port)$(getProperty dcache.bugreporting.se.path)"

    echo ""
    echo "Submitting Bug Report"
    echo "***********************************************"
    echo ""
    echo "The following information will be included in this bug report:"
    echo "  - OS version, CPU architecture"
    echo "  - JVM version"
    echo "  - dCache version"
    echo "  - dCache log files and dump files if they exist. "
    echo ""
    echo "If you do not wish to send all this data with the bug report you can"
    echo "choose what information to include by writing select and pressing return"
    echo "now. If you only press return now you will be given the entire file that"
    echo "will be sent with this report. Please read through the file and erase any"
    echo "information that you do not wish to disclose. [select<return> | <return>]:"

    read choice
    while ! [ "$choice" = "select" ] && ! [ "$choice" = "" ]; do
        echo "Please enter select<return> or just press <return>:"
        echo "You entered:" $choice
        read choice
    done

    # Create basic information that will be included in any report
    # Arrays $descriptionOfCommand $commandsToExecute are used inside this function
    createBasicBugReportFile $tmpReportfile  $prefix $tmpReportPath $descriptionOfCommand $commandsToExecute

    if [ "$choice" = "select" ]; then
        echo ""
        echo "You have chosen to select the information provided with this report"
        echo "piece by piece. Please choose yes(y) or no(n) to include or NOT include"
        echo "the file."
        echo ""
        index=4
        for pieceOfInfo in $files; do
            if [ $DEBUG == 1 ]; then
                echo "PieceOfInfo: $pieceOfInfo"
                echo "TmpReportFile: $tmpReportfile"
                echo "Content header: $pieceOfInfo file"
                echo "Index: $index"
            fi
            addItemToBugReport $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
         done   # End of iterating over files to be published
         printp "Please check the following file content. By saving the file you give your
                consent to send everything that is in the file along with your bug report. Press RETURN to continue:"
         read trash
         vi $tmpReportfile
    else
        index=4
        for pieceOfInfo in $files; do
            printp "PieceOfInfo: $pieceOfInfo"
            if [ -d $pieceOfInfo ]; then
                filesInDirectory=$(ls $pieceOfInfo)
                for file in $filesInDirectory; do
                    printp "\nAdding File in directory $pieceOfInfo: $file"
                    addFileToBugReport $pieceOfInfo$file $tmpReportfile "$file file" $index
                    addEntryToTableOfContent $tmpReportfile $index $file
                    printp "\nFile added: $pieceOfInfo$file \n"
                    index=$(($index + 1))
                done
            else
                echo "Adding single file: $pieceOfInfo"
                addFileToBugReport $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
                addEntryToTableOfContent $tmpReportfile $index $pieceOfInfo
                echo "\nFile added: $pieceOfInfo \n"
                index=$(($index + 1))
            fi
        done
         echo "Everything will be sent with the report. Please check the following file content."
         echo "By saving the file you give your consent to send everything that is in the file"
         echo "along with your bug report."
         echo "Press RETURN to continue:"
         read trash
         if [ $EDITOR ]; then
            $EDITOR $tmpReportfile
         else
            vi $tmpReportfile
         fi
    fi

     # Sending bugreport to support@dcache.org

    printp "Packing file $tmpReportfile"
    tarFile="$tmpReportfile.tar.gz"
    tar czf $tarFile "$tmpReportfile" > /dev/null

    printp "Checking files size of $tarFile"
    tarFileSizeMB=$(du -h "$tarFile" | cut -f 1 | sed 's/[A-Za-z]*//g')
    tarFileSizeMB=${tarFileSizeMB/\.*}

    maxFileSize=$(getProperty dcache.bugreporting.reporter.file.size)
    maxFileSize=${maxFileSize/\.*}

    if [ $tarFileSizeMB -ge $maxFileSize ]; then
        printp "This file is too big to be send via mail. We are trying to copy to the support SE."
        timeStamp=$(date +'%Y-%m-%dT%H:%M:%SUTC')
        url="$FQSN/bugReport-$timeStamp.tar.gz"
        curl -f -T $tarFile $url
        curlResult=$?
        if [ "$curlResult" != 22 ]; then
            printp "File was transfered to our support SE:  $url"
        else
            printp "File transfer to $url failed. dCache support SE might be down. Please report."
        fi
        printp "Do you wish to send this report directly from your current machine [y/n]:"
        read sendDirectByMail
        # This needs to go into a function later
        while ! [ "$sendDirectByMail" = "y" ] && ! [ "$sendDirectByMail" = "n" ]; do
            echo "3 Please enter y for yes or n for no:"
            echo "You entered:" $sendDirectByMail
            read sendDirectByMail
        done
        if [ "$sendDirectByMail" = "y" ]; then
            printp "\n We will now send the bug report to  $supportEmail. Please provide your mail address:"
            read senderMailAddress
            printp "\n Please provide a short description of the bug (one line):"
            read shortDescription
            printp "\n Now please describe the bug in more detail:"
            read longDescription
            sendBugReportMail  "$senderMailAddress" "$supportEmail" "$shortDescription" "$longDescription" "$url" "$tmpReportPath"
        else
            echo "***************************************************************"
            echo "* You can find the file with all the information here:"
            echo "*"
            echo "*" $tmpReportfile
            echo "*" $tarFile
            if [ ! -z "$url" ]; then
                echo "*  also stored at: $url"
            fi
            echo "*"
            echo "* Please take the file and attach it to an e-mail that you send to"
            echo "*"
            echo "*   $supportEmail"
            echo "*"
            echo "* and write a short description of the bug in the subject line and the long"
            echo "* description in the body of the e-mail."
            echo "*"
            echo "* Thank you very much that you took the time to report."
            echo "*"
            echo "***************************************************************"
        fi
    else
        printp "Do you wish to send this report directly from your current machine [y/n]:"
        read sendDirectByMail
        # This needs to go into a function later
        while ! [ "$sendDirectByMail" = "y" ] && ! [ "$sendDirectByMail" = "n" ]; do
            echo "3 Please enter y for yes or n for no:"
            echo "You entered:" $sendDirectByMail
            read sendDirectByMail
        done
        if [ "$sendDirectByMail" = "y" ]; then
            printp "\nWe will now send the bug report to  $supportEmail. Please provide your mail address:"
            read senderMailAddress
            printp "\nPlease provide a short description of the bug (one line):"
            read shortDescription
            printp "\nNow please describe the bug in more detail:"
            read longDescription
            sendBugReportMail  "$senderMailAddress" "$supportEmail" "$shortDescription" "$longDescription" "$tmpReportfile" "$tmpReportPath"
        else
            #showFinalReportMessage $tmpReportfile $tarFile
            echo "***************************************************************"
            echo "* You can find the file with all the information here:"
            echo "*"
            echo "*" $tmpReportfile
            echo "*" $tarFile
            if [ ! -z "$url" ]; then
                echo "*  also stored at: $url"
            fi
            echo "*"
            echo "* Please take the file and attach it to an e-mail that you send to"
            echo "*"
            echo "*   $supportEmail"
            echo "*"
            echo "* and write a short description of the bug in the subject line and the long"
            echo "* description in the body of the e-mail."
            echo "*"
            echo "* Thank you very much that you took the time to report."
            echo "*"
            echo "***************************************************************"
        fi
    fi
}