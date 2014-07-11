DEBUG=1
#set -x
if [ $DEBUG = 1 ]; then
    echo "Shell is: "$SHELL
fi
index=0
heapdumps=""
threaddumps=""


addHeapDump() # $1 = $tmpReportfile $2 = $domains  $3 = tmpHeapdumpFile
{
    local bugReportFile
    local domains
    local heapdumpFile

    bugReportFile="$1"
    domains="$2"
    heapdumpFile="$3"

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

        addEntryToTableOfContent "$bugReportFile" $index "Heap-Dump"
        $heapDumpCommand
        (echo $index. $heapDumpCommand
        echo "------------------------------"
        echo ""
        echo "Please find the heap dump in the tarball that is created with this bug report."
        echo "") >>  "$bugReportFile";
        index=$(($index + 1))
    done
}

addThreadDump() # $1 = $tmpReportfile $2 = $index $3 = $domains
{
    local threadDumpCommand
    threadDumpCommand="dcache dump threads $domains"
    addEntryToTableOfContent "$1" $index "Thread-Dump"

    threadDumpConfirmMessage=$( $threadDumpCommand )
    echo "Please add the files to your report:\n$threadDumpConfirmMessage"

    (echo
    echo $index. $threadDumpCommand
    echo "------------------------------"
    echo ""
    echo "$threadDumpConfirmMessage"
    echo "") >>  "$1";

    index=$(($index + 1))
}

createBasicBugReportFile()
# $1 = filePath
# $2 = tmpBugreportPath
# $3 = commandsToExecute
{
    local tmpFilePath
    local tmpDirPath
    local commandsToExecute
    local yesOrNo

    tmpFilePath="$1"
    tmpDirPath="$2"
    commandsToExecute="$3"
    if [ $DEBUG = 1 ]; then
        printp "DescriptionCommandCouples: $commandsToExecute"
    fi
    numberOfCommands=$(echo $commandsToExecute | tr ';' '\n' |wc -l | bc)
    index=$numberOfCommands

    if [ "$(uname)" = "SunOS" ]; then
        echo "Bug reporting not implemented yet. Ask Christian to do that if needed."  1>&2;
    else
        printp "Creating bug reporting temp directory:  $tmpDirPath"
        if [ ! -d "$tmpDirPath" ]; then
            mkdir -p  "$tmpDirPath"
        fi

        (
        local i
        local j
        echo "Table of Content"
        echo "------------------------------------------"

        echo ""
        echo "#################################################"
        echo "## Reported Commands                           ##"
        echo "#################################################"
        echo ""

        IFS=';'
        j=0
        for commandDescriptionCouple in $commandsToExecute; do
            j=$((j+1))
            commandDescCouple=$(echo $commandDescriptionCouple | cut -d ';' -f $j)
            commandDesc=$(expr "${commandDescCouple}" : "\(.*\)::.*$")
            commandDesc=$(echo $commandDesc | sed 's/^ *//')
            echo "$j. $commandDesc"
        done

        echo ""
        echo "#################################################"
        echo "## Reported Files                              ##"
        echo "#################################################"
        echo ""

        echo "----------endTableContent-----------------"
        echo ""

        i=0

        for commandDescriptionCouple in $commandsToExecute; do
            i=$((i+1))
            commandDescCouple=$(echo $commandDescriptionCouple | cut -d ';' -f $i)
            commandDesc=$(expr "${commandDescCouple}" : "\(.*\)::.*$")
            commandDesc=$(echo $commandDesc | sed 's/^ *//')
            command=$(expr "${commandDescCouple}" : ".*::\(.*$\)")
            echo "\n"
            echo $i. $commandDesc
            echo "----------------------"
            echo "$command"
#           eval "$command" 2>&1
            if eval "$command" 2>&1; then
                continue;
            else
                echo "Command: \"$command\" failed to execute correctly";
            fi
        done
        unset IFS
        ) > "$tmpFilePath"
    fi
    index=$(($index + 1))
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
    if [ $yesOrNo = "y" ]; then
        echo "\nThese are the domains on your machine:"
        echo $(getProperty dcache.domains)
        echo "\nPlease provide a space separated list of domains, which will be included in the dump:"
        read domains
        addThreadDump $tmpReportfile $index $domains
    fi
}

writeFileToBugReport() # $1 = fileToAddPath $2 = bugReportFilePath   $3 = headline   $4 = index
{
    local fileToAddPath
    local bugReportFilePath
    local headline

    fileToAddPath="$1"
    bugReportFilePath="$2"
    headline="$3"

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
    '$2'. '$3'
    ' "$1"
}

addFileToBugReport() # $1 = fileURI $2 = tmpReportfile $3 = index
{
    local pieceOfInfo
    local tmpReportfile
    local yesOrNo

    pieceOfInfo="$1"
    tmpReportfile="$2"

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
    if [ $yesOrNo = "y" ]; then
        writeFileToBugReport "$pieceOfInfo" "$tmpReportfile" "$pieceOfInfo file" $index
        addEntryToTableOfContent "$tmpReportfile" $index "$pieceOfInfo"
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
    local pieceOfInfo="$1"
    local tmpReportfile="$2"

    writeFileToBugReport $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
}

addAllFilesInDirectory() # $1 = directory
{
    addEntryToTableOfContent $tmpReportfile $index "$item"
    index=$(($index + 1))
    allFilesInDirectory=$(ls $item)
    for itemInDir in $allFilesInDirectory; do
        if [ -d $itemInDir ]; then
            addItemToBugReport $itemInDir $tmpReportfile $index
        else
            writeFileToBugReport $item/$itemInDir $tmpReportfile "$item/$itemInDir file" $index
            addEntryToTableOfContent $tmpReportfile $index $item/$itemInDir
            index=$(($index + 1))
            echo "File added: $item/$itemInDir"
        fi
    done
}

addItemToBugReport() # $1 = directory  $2 = $tmpReportfile $3 = index
{
    local item
    local tmpReportfile
    local yesOrNo

    item="$1"
    tmpReportfile="$2"

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
        printp "Include entire directory $item
                yes (y) / select one by one (s) / no (n):"
        read yesOrNo
        # This needs to go into a function later
        while ! [ "$yesOrNo" = "y" ] && ! [ "$yesOrNo" = "n" ] && ! [ "$yesOrNo" = "s" ]; do
            echo "Please enter y for yes or n for no or s for selecting one by one:"
            echo "You entered:" $yesOrNo
            read yesOrNo
        done
        case "$yesOrNo" in
            y)
            addAllFilesInDirectory $item $tmpReportfile $index
            ;;

            s)
            local itemsInDir
            itemsInDir=$(ls $item)
            for itemInDir in $itemsInDir; do
                addItemToBugReport $item/$itemInDir $tmpReportfile $index
            done
            ;;

            *)
            echo "Not adding any files of directory $item"
            ;;
        esac
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
# $3 =  URL to tarfile on bugreport SE
# $4 = tar file
{
    local sender
    local destination
    local shortDescription
    local longDescription
    local fileUrlOnSE
    local tarFilePath
    local smtpServer
    local mailClientChoice

    sender="$1"
    destination="$2"
    fileUrlOnSE="$3"
    tarFilePath="$4"

    which telnet > /dev/null
    telnetPresent=$?
    which mailx  > /dev/null
    mailxPresent=$?
    which sendmail > /dev/null
    sendmailPresent=$?

    smtpServer=$(getProperty dcache.bugreporting.smtp)

    if [ $telnetPresent -eq 0 ]; then
        while [ -z "$smtpServer" ];
        do
            if [ $DEBUG = 1 ]; then
                echo "smtpServer: $smtpServer"
            fi
            printp "Please enter your smtp server here or set the dcache.bugreporting.smtp
                    property in in your $(getProperty dcache.paths.setup) file:"
            read smtpServer
        done
        printpi "Telnet(1) - Telnet available."
    fi
    if [ $mailxPresent -eq 0 ]; then
        printpi "mailx(2) - you need to have your local mail client configured"
    fi
    if [ $sendmailPresent -eq 0 ]; then
        printpi "sendmail(3) - you need to have your local mail client configured."
    fi

    printp "\nPlease enter the number in brackets to use one of these clients to send your mail:"
    echo "\nChoice:"
    read mailClientChoice

    printp "Please provide a short description of the bug (one line):"
    read shortDescription
    printp "Now please describe the bug in more detail:"
    read longDescription

    case "$mailClientChoice" in
        3)
        ( echo "------------------------------------------"
          echo "Problem Description"
          echo "------------------------------------------"
          echo "$longDescription"
          echo ""
          echo "----------------------------------------------"
          echo "Bugreport file URL on dCache SE: $fileUrlOnSE"
          echo "-----------------------------------------------"
          echo "\n"
        ) | sendmail $destination
        ;;
        2)
        from=$sender smtp=$smtpServer \
                  mailx -n -s "$shortDescription" \
                  $destination  < /dev/null
        ;;
        1)
           count=1
        if [ $DEBUG = 1 ]; then
            echo "tar file path: $tarFilePath"
            echo "Address report was sent from: $sender"
            echo "Address report will be sent to: $destination"
        fi
        while [ $count = 1 ];
        do
            ( echo open $smtpServer 25
              sleep 12
              echo "helo $smtpServer"
              echo "MAIL From: $sender"
              echo "RCPT To: $destination"
              echo 'DATA'
              echo "From: $sender"
              echo "To: $destination"
              echo "Subject: $shortDescription"
              echo "MIME-Version: 1.0"
              echo "Content-Type: multipart/mixed; boundary=\"-q1w2e3r4t5\""
              echo "---q1w2e3r4t5"
              echo "Content-Transfer-Encoding: quoted-printable"
              echo "Content-Type: text/plain; charset=us-ascii"
              echo "------------------------------------------"
              echo "Problem Description"
              echo "------------------------------------------"
              echo "$longDescription"
              echo ""
              echo "----------------------------------------------"
              echo "Bugreport file URL on dCache SE: $fileUrlOnSE"
              echo "-----------------------------------------------"
              echo "\n"
              echo "---q1w2e3r4t5"
              echo "."
              echo "quit") | telnet
              count=2
              echo "Telnet done."
        done
        rm -r "$tmpDirPath"
        ;;
        *)
        echo "You have not chosen a mail program. Please chose one of the above."
    esac
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
    local supportEmail
    local descriptionOfCommand
    local commandsToExecute
    local files
    local tmpReportPath
    local timeStamp
    local tmpReportPath
    local tmpReportfile
    local heapdumpFileName
    local tmpHeapdumpFile
    local FQSN
    local choice
    local yesOrNo
    local trash
    local smtpServer
    local checkedMail
    local senderMailAddress

    supportEmail=$(getProperty dcache.bugreporting.supporter.email)
    commandsToExecute=$(getProperty dcache.bugreporting.commands)
    files=$(getProperty dcache.bugreporting.paths)
    tmpReportPath=$(getProperty dcache.bugreporting.tmpfilepath)
    timeStamp=$(date +'%Y-%m-%dT%H:%M:%SUTC')
    tmpReportPath=$tmpReportPath/$timeStamp
    tmpReportfile=$tmpReportPath/bugReportFile.tmp
    heapdumpFileName=$(getProperty dcache.bugreporting.heapdumpfile.name)
    tmpHeapdumpFile=$tmpReportPath/$heapdumpFileName
    FQSN="$(getProperty dcache.bugreporting.se.name):$(getProperty dcache.bugreporting.se.port)$(getProperty dcache.bugreporting.se.path)"
    smtpServer=$(getProperty dcache.bugreporting.smtp)
    senderMailAddress=$(getProperty dcache.bugreporting.reporter.email)

    if [ $# -ne 0 ]; then

        command="$1"
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
    while [ "$choice" != "select" ] &&  [ "$choice" != "" ]; do
        echo "Please enter select<return> or just press <return>:"
        echo "You entered:" $choice
        read choice
    done

    # Create basic information that will be included in any report
    createBasicBugReportFile "$tmpReportfile" "$tmpReportPath" "$commandsToExecute"

    if [ "$choice" = "select" ]; then
        printp " You have chosen to select the information provided with this report
                 piece by piece. Please choose yes(y) or no(n) to include or NOT include
                 the file.\n"
        for pieceOfInfo in $files; do
            if [ $DEBUG = 1 ]; then
                echo "PieceOfInfo: $pieceOfInfo"
                echo "TmpReportFile: $tmpReportfile"
                echo "Content header: $pieceOfInfo file"
                echo "Index: $index"
            fi
            addItemToBugReport $pieceOfInfo $tmpReportfile $index
         done
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
                    echo "File added: $pieceOfInfo/$file"
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

        printp "Everything will be sent with the report. Please check the following file content.
        By saving the file you give your consent to send everything that is in the file
        along with your bug report.
        Press RETURN to continue:"
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
    if [ $yesOrNo = "y" ]; then
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

    echo "Deleting tmp bug report directory: $tmpReportPath"
    rm -rf $tmpReportPath

    maxFileSize=$(getProperty dcache.bugreporting.reporter.file.size)
    maxFileSize=${maxFileSize/\.*}


    timeStamp=$(date +'%Y-%m-%dT%H:%M:%SUTC')
    url="$FQSN/bugReport-$timeStamp.tar.gz"
    echo "Sending bugreport tar to $url"
    curl -f -T $tarFile $url
    curlResult=$?
    if [ "$curlResult" != 22 ]; then
        printp "File was transfered to our support SE:  $url"
    else
        printp "File transfer to $url failed. dCache support SE might be down. Please report."
    fi
    printp "Do you wish to e-mail this report directly from your current machine [y/n]:"
    read sendDirectByMail
    # This needs to go into a function later
    while ! [ "$sendDirectByMail" = "y" ] && ! [ "$sendDirectByMail" = "n" ]; do
        echo "3 Please enter y for yes or n for no:"
        echo "You entered:" $sendDirectByMail
        read sendDirectByMail
    done
    checkedMail="Mail not checked yet"
    if [ "$sendDirectByMail" = "y" ]; then
        while [ -z "$senderMailAddress" ] && [ "$senderMailAddress" != "$checkedMail" ]
        do
                if [ $DEBUG = 1 ]; then
                    echo "sendMail check loop"
                fi
                if [ -z "$senderMailAddress" ]; then
                    printp "You have not specified an reporter e-mail address, please
                            set the dcache.bugreporting.reporter.email
                            property in your $(getProperty dcache.paths.setup) file
                            or enter the sender mail address here and press <return>:"
                    read senderMailAddress
                fi

                if [ $DEBUG = 1 ]; then
                    echo "Checking sendermail"
                fi
                checkedMail=$(echo "$senderMailAddress" | grep '^[A-z0-9\._%+-]+@[A-z0-9\.-]+\.[A-z]{2,4}$' || :)

                if [ $DEBUG = 1 ]; then
                    echo "After check sendermail"
                    echo "checkedMail is: $checkedMail"
                    echo "senderMailAddress: $senderMailAddress"
                fi

                if [ "$senderMailAddress" != "$checkedMail" ]; then
                    printp "Please check your e-mail format. You entered: $senderMailAddress. Please reenter the
                    a correctly formated e-mail address:"
                    read senderMailAddress
                else
                    printp "The bug report will be sent using $senderMailAddress."
                fi
        done
        if [ $DEBUG = 1 ]; then
            echo "Reporter e-mail set to: $senderMailAddress"
        fi

        sendBugReportMail  "$senderMailAddress" "$supportEmail" "$url" "$tarFile"
        rm "$tarFile"
    else
        showFinalReportMessage $url $tarFile
    fi
}