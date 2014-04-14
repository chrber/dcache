DEBUG=1
#set -x
index=0
heapdumps=""
threaddumps=""


addHeapDump() # $1 = $tmpReportfile $2 = $domains  $3 = tmpHeapdumpFile
{
    local bugReportFile=$1
    local domains=$2
    local heapdumpFile=$3


    if [ $DEBUG = 1 ]; then
        echo "Heap dumping!!!"
        echo "Using bug report file: $bugReportFile"
        echo "Using HeapDump file template: $heapdumpFile"
        echo "For domains: $domains"
    fi

    for domain in $domains; do
        domainHeapdumpFile="$heapdumpFile-$domain"
        heapDumpCommand="dcache dump heap $domain $domainHeapdumpFile"

        if [ $DEBUG = 1 ]; then
            echo "For domain: $domain create file: $domainHeapdumpFile"
            echo "Executing heap dump command: $heapDumpCommand"
        fi

        addEntryToTableOfContent $bugReportFile $index "Heap-Dump"
        $heapDumpCommand
        (echo $index. $heapDumpCommand
        echo "------------------------------"
        echo ""
        echo "Please find the heap dump in the tarball that is created with this bug report."
        echo "") >>  $bugReportFile;
        index=$(($index + 1))
    done
}

addThreadDump() # $1 = $tmpReportfile $2 = $index $3 = $domains
{
    local threadDumpCommand="dcache dump threads $domains"
    addEntryToTableOfContent $1 $index "Thread-Dump"

    threadDumpConfirmMessage=$( $threadDumpCommand )
    echo "Please add the files to your report:\n$threadDumpConfirmMessage"

    (echo
    echo $index. $threadDumpCommand
    echo "------------------------------"
    echo ""
    echo "$threadDumpConfirmMessage"
    echo "") >>  $1;

    index=$(($index + 1))
}

createBasicBugReportFile()
# $1 = filePath
# $2 = tmpBugreportPath
# $3 = descriptionOfCommand
# $4 = commandsToExecute
{
    local tmpFilePath="$1"
    local tmpDirPath="$2"
    local descriptionOfCommand="$3"
    local commandsToExecute="$4"

    numberOfCommandDescriptions=$(echo $descriptionOfCommand | tr ';' '\n' | wc -l | bc)
    numberOfCommands=$(echo $commandsToExecute | tr ';' '\n' |wc -l | bc)

    if [ $numberOfCommandDescriptions !=  $numberOfCommands ]; then
        printp "Number of command descriptions ($numberOfCommandDescriptions) dissimilar to number of commands ($numberOfCommands)."
        exit 1;
    fi

    index=$numberOfCommands

    if [ "$(uname)" = "SunOS" ]; then
        echo "Bug reporting not implemented yet. Ask Christian to do that if needed."
    else
        printp "Creating bug reporting temp directory:  $tmpDirPath"
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

        i=0

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
    if [ $DEBUG = 1 ]; then
        printp "Create basic bugreport, index at: $index"
    fi

    echo "Do you wish to include a thread dump in this report y/n:"
    read yesOrNo
    while ! [ "$yesOrNo" = "y" ] && ! [ "$yesOrNo" = "n" ]; do
        echo "Please enter y for yes or n for no:"
        echo "You entered:" $yesOrNo
        read yesOrNo
    done
    if [[ $yesOrNo = "y" ]]; then
        echo "\nThese are the domains on your machine:"
        echo $(getProperty dcache.domains)
        echo "\nPlease provide a space separated list of domains, which will be included in the dump:"
        read domains
        addThreadDump $tmpReportfile $index $domains
    fi
}

writeFileToBugReport() # $1 = fileToAddPath $2 = bugReportFilePath   $3 = headline   $4 = index
{
    local fileToAddPath=$1
    local bugReportFilePath=$2
    local headline=$3

    if [ $DEBUG = 1 ]; then
       printp "Printing file"
       printp "File to add:  $fileToAddPath"
       printp "BugReport file: $bugReportFilePath"
       printp "Headline: $headline"
    fi


    (echo $index. $headline
    echo "------------------------------"
    echo ""
    cat $fileToAddPath
    echo "") >>  $bugReportFilePath;
}

addEntryToTableOfContent() # $1 = $tmpReportfile $2 = $index $3 = $pieceOfInfo
{
    sed -ie '/endTableContent/ i\
    \'$2'. '$3'
    ' $1
}

addFileToBugReport() # $1 = fileURI $2 = tmpReportfile $3 = index
{
    local pieceOfInfo=$1
    local tmpReportfile=$2

    if [ $DEBUG = 1 ]; then
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
    if [[ $yesOrNo = "y" ]]; then
        writeFileToBugReport $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
        addEntryToTableOfContent $tmpReportfile $index $pieceOfInfo
        if [ $DEBUG = 1 ]; then
            printp "Index currently is: $index"
        fi
        index=$(($index + 1))
        if [ $DEBUG = 1 ]; then
            printp "File added: $pieceOfInfo"
        fi
    else
        if [ $DEBUG = 1 ]; then
            printp "Chosen not to add $pieceOfInfo."
        fi
    fi
}

addFileToBugReportWithoutQuestion() # $1 = fileURI $2 = tmpReportfile $3 = index
{
    local pieceOfInfo=$1
    local tmpReportfile=$2

    writeFileToBugReport $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
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
            index=$(($index + 1))
            printp "\n File added: $item/$itemInDir \n"
        fi
    done
}

addItemToBugReport() # $1 = directory  $2 = $tmpReportfile $3 = index
{
    local item="$1"
    local tmpReportfile="$2"


    if [ $DEBUG = 1 ]; then
        echo "************************************"
        echo "Function: addItemToBugReport"
        echo "Item: $item"
        echo "TmpReportFile: $tmpReportfile"
        echo "Index: $index\n"
    fi

    # refine logic here as there can be files coming as pieceOfInfo, this should not be

    if [ -d $item ]; then
        if [ $DEBUG = 1 ]; then
            echo "Adding directory: $item"
        fi
        echo "Include entire directory $item yes (y) / select one by one (s) / no (n):"
        read yesOrNo
        # This needs to go into a function later
        while ! [ "$yesOrNo" = "y" ] && ! [ "$yesOrNo" = "n" ] && ! [ "$yesOrNo" = "s" ]; do
            echo "Please enter y for yes or n for no or s for selecting one by one:"
            echo "You entered:" $yesOrNo
            read yesOrNo
        done
        if [[ $yesOrNo = "y" ]]; then
            addAllFilesInDirectory $item $tmpReportfile $index
        fi
        if [[ $yesOrNo = "s" ]]; then
            local itemsInDir=$(ls $item)
            for itemInDir in $itemsInDir; do
                addItemToBugReport $item/$itemInDir $tmpReportfile $index
            done
        else
            echo "Not adding any files of directory $item"
        fi
    else
        if [ $DEBUG = 1 ]; then
            echo "Adding file: $item"
            echo "BEFORE - Index now at: $index"
        fi
        addFileToBugReport $item $tmpReportfile $index
        if [ $DEBUG = 1 ]; then
            echo "AFTER Index now at: $index"
        fi
    fi
}

sendBugReportMail()
# $1 = sender mail address
# $2 = destination mail address
# $3 = short description of problem
# $4 = long description of problem
# $5 = URL to tarfile on bugreport SE
# $6 = tar file
{
    local tmpMailrc=$MAILRC
    local sender=$1
    local destination=$2
    local shortDescription=$3
    local longDescription=$4
    local fileUrlOnSE="$5"
    local tarFilePath="$6"
    local smtpServer=$(getProperty dcache.bugreporting.smtp)

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
        sendmail $2 <  $tarFilePath
    else if [ $mailClientChoice = 2 ]; then
        tmpMailrc=$MAILRC
        from=$1 smtp=$smtpServer \
                  mailx -n -s "$3" \
                  $2 < $tarFilePath
        MAILRC=$tmpMailrc

    else if [ $mailClientChoice = 1 ]; then
        count=1
        if [ $DEBUG = 1 ]; then
            echo "tar file path to be base64 encoded: $tarFilePath"
        fi
        uuencodedFile=$(uuencode -m $tarFilePath $(basename $tarFilePath))
        while [ $count = 1 ]
        do
            ( echo open $smtpServer 25
              sleep 5
              echo 'helo $smtpServer'
              sleep 5
              echo "MAIL From: $1"
              echo "RCPT To: $2"
              echo 'DATA'
              sleep 5
              echo "From: $1"
              echo "To: $2"
              echo "Subject: $3"
              echo "MIME-Version: 1.0"
              echo "Content-Type: multipart/mixed; boundary=\"-q1w2e3r4t5\""
              echo "---q1w2e3r4t5"
              echo "Content-Transfer-Encoding: quoted-printable"
              echo "Content-Type: text/plain; charset=us-ascii"
              echo "------------------------------------------"
              echo "Long description of problem"
              echo "------------------------------------------"
              echo "$longDescription"
              echo ""
              echo "----------------------------------------------"
              echo "Bugreport file URL on dCache SE: $fileUrlOnSE"
              echo "-----------------------------------------------"
              echo "\n"
              echo "---q1w2e3r4t5"
              echo "---q1w2e3r4t5"
              echo "Content-Disposition: attachment; filename=\"$(basename $tarFilePath)\""
              echo "Content-Type: application/x-gzip;name=\"$(basename $tarFilePath)\""
              echo "Content-Transfer-Encoding: base64"
              echo "$uuencodedFile"
              echo "---q1w2e3r4t5"
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

showFinalReportMessage() # $1 = URL  $2 = tarfile
{
    echo "***************************************************************"
    if [ -f "$2" ]; then
        echo "* You can find the file with all the information here:"
        echo "*"
        echo "* $2"
        echo "*"
    fi
    if [ ! -z "$1" ]; then
        echo "*"
        echo "* The report tar file has been stored on our bugreport SE:\n"
        echo "* $url"
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
}

processBugReport()
{
    supportEmail=$(getProperty dcache.bugreporting.supporter.email)
    descriptionOfCommand=$(getProperty dcache.bugreporting.commands.description)
    commandsToExecute=$(getProperty dcache.bugreporting.commands)

    files=$(getProperty dcache.bugreporting.paths)
    tmpReportPath=$(getProperty dcache.bugreporting.tmpfilepath)
    timeStamp=$(date +'%Y-%m-%dT%H:%M:%SUTC')
    tmpReportPath=$tmpReportPath/$timeStamp
    tmpReportfile=$tmpReportPath/bugReportFile.tmp
    heapdumpFileName=$(getProperty dcache.bugreporting.heapdumpfile.name)
    tmpHeapdumpFile=$tmpReportPath/$heapdumpFileName
    FQSN="$(getProperty dcache.bugreporting.se.name):$(getProperty dcache.bugreporting.se.port)$(getProperty dcache.bugreporting.se.path)"

    if [ $# -ne 0 ]; then

        command=$1
        shift
        filesFromCommandLine="$@"
        if [ $DEBUG = 1 ]; then
            printp "Command added: $command"
            printp "Files added as parameters: $filesFromCommandLine"
        fi

        if [ "$command" = "add" ]; then
            if [ $DEBUG = 1 ]; then
                echo "Command add"
            fi
            files="$files $filesFromCommandLine"
        fi

        if [ "$command" = "only" ]; then
            if [ $DEBUG = 1 ]; then
                echo "Command only"
            fi
            files=$filesFromCommandLine
        fi
    fi

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
    createBasicBugReportFile "$tmpReportfile" "$tmpReportPath" "$descriptionOfCommand" "$commandsToExecute"

    if [ "$choice" = "select" ]; then
        echo ""
        echo "You have chosen to select the information provided with this report"
        echo "piece by piece. Please choose yes(y) or no(n) to include or NOT include"
        echo "the file."
        echo ""
        for pieceOfInfo in $files; do
            if [ $DEBUG = 1 ]; then
                echo "PieceOfInfo: $pieceOfInfo"
                echo "TmpReportFile: $tmpReportfile"
                echo "Content header: $pieceOfInfo file"
                echo "Index: $index"
            fi
            addItemToBugReport $pieceOfInfo $tmpReportfile $index
         done   # End of iterating over files to be published
         printp "Please check the following file content. By saving the file you give your
                consent to send everything that is in the file along with your bug report. Press RETURN to continue:"
         read trash
         if [ $EDITOR ]; then
           $EDITOR $tmpReportfile
        else
           vi $tmpReportfile
        fi
    else
        if [ $DEBUG = 1 ]; then
            printp "Adding everything to the report"
            printp "Files are: $files"
        fi
        for pieceOfInfo in $files; do
            if [ $DEBUG = 1 ]; then
                printp "PieceOfInfo: $pieceOfInfo"
            fi
            if [ -d $pieceOfInfo ]; then
                filesInDirectory=$(ls $pieceOfInfo)
                for file in $filesInDirectory; do
                    if [ $DEBUG = 1 ]; then
                        echo "\nAdding File in directory $pieceOfInfo: $file"
                    fi
                    addFileToBugReportWithoutQuestion $pieceOfInfo/$file $tmpReportfile $index
                    addEntryToTableOfContent $tmpReportfile $index $file
                    printp "File added: $pieceOfInfo/$file"
                    index=$(($index + 1))
                done
            else
                if [ $DEBUG = 1 ]; then
                    echo "Adding single file: $pieceOfInfo"
                fi
                addFileToBugReportWithoutQuestion $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
                addEntryToTableOfContent $tmpReportfile $index $pieceOfInfo
                echo "File added: $pieceOfInfo"
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

    echo "Include heap dump y/n:"
    read yesOrNo
    while ! [ "$yesOrNo" = "y" ] && ! [ "$yesOrNo" = "n" ]; do
        echo "Please enter y for yes or n for no:"
        echo "You entered:" $yesOrNo
        read yesOrNo
    done
    if [[ $yesOrNo = "y" ]]; then
        echo "These are the domains on your machine:"
        echo $(getProperty dcache.domains)
        echo
        echo "Please provide a space separated list of domains, which will be included in the dump:"
        read domains
        if [ $DEBUG = 1 ]; then
            echo "Calling addHeapDump with parameters: $tmpReportfile $domains $tmpHeapdumpFile"
        fi
        addHeapDump "$tmpReportfile" "$domains" "$tmpHeapdumpFile"
    fi

    # Sending bugreport to support@dcache.org

    printp "Packing file $tmpReportfile"
    tarFile="$tmpReportPath.tar.gz"
    tar czf $tarFile -C "$tmpReportPath" . > /dev/null

    echo "Checking files size of $tarFile"
    tarFileSizeMB=$(du -hm "$tarFile" | cut -f 1 | sed 's/[A-Za-z]*//g')
    tarFileSizeMB=${tarFileSizeMB/\.*}
    echo "Deleting tmp bug report directory: $tmpReportPath"
    rm -rf $tmpReportPath

    maxFileSize=$(getProperty dcache.bugreporting.reporter.file.size)
    maxFileSize=${maxFileSize/\.*}

    if [ $tarFileSizeMB -ge $maxFileSize ]; then
        printp "This file is too big to be send via mail.
                You have set maximum size to: $maxFileSize MB
                The file size of $tarFile is $tarFileSizeMB MB
                We are trying to copy to the support SE."
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
            printp "\nWe will now send the bug report to  $supportEmail. Please provide your mail address ($(getProperty dcache.bugreporting.reporter.email)):"
            read senderMailAddress
            printp "\n Please provide a short description of the bug (one line):"
            read shortDescription
            printp "\n Now please describe the bug in more detail:"
            read longDescription
            sendBugReportMail  "$senderMailAddress" "$supportEmail" "$shortDescription" "$longDescription" "$url" "$tarFile"
            rm -f "$tarFile"
        else
            showFinalReportMessage $url $tarFile
        fi
    else   # tar file is small enough to be sent by e-mail
        printp "Do you wish to send this report directly from your current machine [y/n]:"
        read sendDirectByMail
        # This needs to go into a function later
        while ! [ "$sendDirectByMail" = "y" ] && ! [ "$sendDirectByMail" = "n" ]; do
            echo "3 Please enter y for yes or n for no:"
            echo "You entered:" $sendDirectByMail
            read sendDirectByMail
        done
        if [ "$sendDirectByMail" = "y" ]; then
            standardReporterAddress=$(getProperty dcache.bugreporting.reporter.email)
            printp "\nWe will now send the bug report to $supportEmail. The mail will be sent using $standardReporterAddress, please specify a different address, if desired:"
            read senderMailAddress
            if [ "$senderMailAddress" = "" ]; then
                senderMailAddress=$standardReporterAddress
            fi
            if [ $DEBUG = 1 ]; then
                echo "Reporter e-mail set to: $senderMailAddress"
            fi
            printp "\nPlease provide a short description of the bug (one line):"
            read shortDescription
            printp "\nNow please describe the bug in more detail:"
            read longDescription
            sendBugReportMail  "$senderMailAddress" "$supportEmail" "$shortDescription" "$longDescription" "$tarFile" "$tarFile"
        else
            showFinalReportMessage $url
        fi
    fi
}