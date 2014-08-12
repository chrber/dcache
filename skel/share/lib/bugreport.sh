DEBUG=0
#set -x
set -o posix

index=0

debugStatement() #$1 = Content of statement
{
    if [ $DEBUG = 1 ]; then
        echo ""
        echo "======== DEBUG ========"
        echo $1
        echo "======== DEBUG ========"
        echo ""
    fi
}

debugStatement "Shell is: $SHELL"

checkForCorrectYesOrNoAnswer()
{
    local yesOrNo
    until [ "$yesOrNo" = "y" ] || [ "$yesOrNo" = "n" ]; do
        echo "Enter y or n" 1>&2
        read yesOrNo
    done
    echo "$yesOrNo"
}

cleanUp()
{
    local tmpDir
    local yesOrNo

    tmpDir=$(getProperty dcache.submit.bugreport.tmpfilepath)

    if [ -d "$tmpDir" ]; then
        echo "Do you wish to delete $tmpDir (y/n):"
        yesOrNo=$(checkForCorrectYesOrNoAnswer)
        if [ $yesOrNo = "y" ]; then
            rm -r "$tmpDir"
            debugStatement "Deleted $tmpDir"
        fi
    fi
}

# Catching CTRL+c
trap "echo CTRL-C was pressed.; cleanUp; exit 1"  2


addHeapDump() # $1 = $tmpReportfile $2 = $domains  $3 = tmpHeapdumpFile
{
    local bugReportFile
    local domains
    local heapdumpFile

    bugReportFile="$1"
    domains="$2"
    heapdumpFile="$3"

    debugStatement "Heap dumping\n
                    Using bug report file: $bugReportFile\n
                    Using HeapDump file template: $heapdumpFile\n
                    For domains: $domains"

    for domain in $domains; do
        domainHeapdumpFile="$heapdumpFile-$domain"
        heapDumpCommand="dcache dump heap $domain $domainHeapdumpFile"

        debugStatement "For domain: $domain create file: $domainHeapdumpFile\n
                        Executing heap dump command: $heapDumpCommand"

        addEntryToTableOfContent "$bugReportFile" $index "Heap-Dump"
        $heapDumpCommand
        (echo""
        echo $index. $heapDumpCommand
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
    local domains=$3
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
    local domainChoice
    local domains
    local tempIndex

    tmpFilePath="$1"
    tmpDirPath="$2"
    commandsToExecute="$3"
    domainChoice=""
    domains=""

    debugStatement "DescriptionCommandCouples: $commandsToExecute"

    numberOfCommands=$(echo "$commandsToExecute" |wc -l)
    index=$numberOfCommands

    debugStatement "Number of commands: $index"

    printp "Creating bug reporting temp directory:  $tmpDirPath"
    if [ ! -d "$tmpDirPath" ]; then
        mkdir -p  "$tmpDirPath"
    fi

    tempIndex=0
    commandDescriptions=$(while IFS= read -r line;
    do
        tempIndex=$((tempIndex+1))
        commandDesc=$(expr "${line}" : "\(.*\)::.*$")
        commandDesc=$(echo $commandDesc | sed 's/^ *//')
        echo "$tempIndex. $commandDesc"
    done <<< "$commandsToExecute")

    tempIndex=0
    headlinePlusCommand=$(while IFS= read -r line;
    do
        tempIndex=$((tempIndex+1))
        commandDesc=$(expr "${line}" : "\(.*\)::.*$")
        commandDesc=$(echo $commandDesc | sed 's/^ *//')
        command=$(expr "${line}" : ".*::\(.*$\)")
        echo "\n"
        echo $tempIndex. $commandDesc
        echo "----------------------"
        echo "$command"
        eval "$command" 2>&1 || echo "Command: \"$command\" failed to execute correctly"

    done <<<"$commandsToExecute")

    (
    echo "Table of Content"
    echo "------------------------------------------"

    echo ""
    echo "#################################################"
    echo "## Reported Commands                           ##"
    echo "#################################################"
    echo ""

    echo "$commandDescriptions"

    echo ""
    echo "#################################################"
    echo "## Reported Files                              ##"
    echo "#################################################"
    echo ""

    echo "----------endTableContent-----------------"
    echo ""

    echo "$headlinePlusCommand"
    echo ""
    ) > "$tmpFilePath"
    index=$(($index + 1))

    debugStatement "Created basic bugreport, index at: $index"

    echo "Do you wish to include a thread dump in this report y/n:"
    yesOrNo=$(checkForCorrectYesOrNoAnswer)
    domains=$(getProperty dcache.domains)
    if [ $yesOrNo = "y" ]; then
        echo "\nThese are the domains on your machine:"
        echo $domains
        while [[ $(echo "$domains" | grep -c "$domainChoice") -eq 0 || -z "$domainChoice" ]]; do
            debugStatement "$domainChoice not in \"$domains\"\n
                            Result was: $(echo "$domains" | grep -c "$domainChoice")"
            printp "Please provide a valid space separated list of the domains shown above, which will be included in the dump:"
            read domainChoice
        done
        debugStatement "Adding thread dumps for domains: $domainChoice"
        addThreadDump $tmpReportfile $index $domainChoice
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

    debugStatement "Printing file\n
                    File to add:  $fileToAddPath\n
                    BugReport file: $bugReportFilePath\n
                    Headline: $headline"

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

requestToAddFile() # $1 = fileURI $2 = tmpReportfile $3 = index
{
    local pieceOfInfo
    local tmpReportfile
    local yesOrNo

    fileUri="$1"
    tmpReportfile="$2"

    debugStatement "Function: requestToAddFile\n
                    FileUri: $fileUri\n
                    TmpReportFile: $tmpReportfile\n
                    Index: $index"

    echo "Include $fileUri y/n:"
    yesOrNo=$(checkForCorrectYesOrNoAnswer)
    if [ $yesOrNo = "y" ]; then
        writeFileToBugReport "$fileUri" "$tmpReportfile" "$fileUri file" $index
        addEntryToTableOfContent "$tmpReportfile" $index "$fileUri"

        debugStatement "Index currently is: $index"

        index=$(($index + 1))

        debugStatement "File added: $fileUri"
    else
        debugStatement "Chosen not to add $fileUri."
    fi
}

addFile() # $1 = fileURI $2 = tmpReportfile $3 = index
{
    local fileUri="$1"
    local tmpReportfile="$2"

    writeFileToBugReport $fileUri $tmpReportfile "$fileUri file" $index
}

addAllFilesInDirectory() # $1 = directory   $2 = $tmpReportfile  $3 = $index
{
    local directory
    local tmpReportfile
    local index

    directory=$1
    tmpReportfile=$2
    index=$3

    addEntryToTableOfContent $tmpReportfile $index "$directory"
    index=$(($index + 1))
    allFilesInDirectory=$(ls $directory)
    for itemInDir in $allFilesInDirectory; do
        if [ -d $itemInDir ]; then
            addItemToBugReport $itemInDir $tmpReportfile $index
        else
            writeFileToBugReport $directory/$itemInDir $tmpReportfile "$directory/$itemInDir file" $index
            addEntryToTableOfContent $tmpReportfile $index $directory/$itemInDir
            index=$(($index + 1))
            echo "File added: $directory/$itemInDir"
        fi
    done
}

addItemToBugReport() # $1 = directory or file  $2 = $tmpReportfile $3 = index
{
    local item
    local tmpReportfile
    local choice

    item="$1"
    tmpReportfile="$2"

    debugStatement "Function: addItemToBugReport\n
                    Item: $item\n
                    TmpReportFile: $tmpReportfile\n
                    Index: $index"

    if [ -d $item ]; then

        debugStatement "Adding directory: $item"

        printp "Include entire directory $item
                yes (y) / select one by one (s) / no (n):"
        read choice
        # This needs to go into a function later
        while ! [ "$choice" = "y" ] && ! [ "$choice" = "n" ] && ! [ "$choice" = "s" ]; do
            echo "Please enter y for yes or n for no or s for selecting one by one:"
            echo "You entered:" $choice
            read choice
        done
        case "$choice" in
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

        debugStatement "Adding file: $item\n
                        BEFORE - Index now at: $index"

        requestToAddFile $item $tmpReportfile $index

        debugStatement "AFTER Index now at: $index"

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

    smtpServer=$(getProperty dcache.submit.bugreport.smtp)

    if [ $telnetPresent -eq 0 ]; then
        while [ -z "$smtpServer" ];
        do

            debugStatement "smtpServer: $smtpServer"

            printp "Please enter your smtp server here or set the dcache.submit.bugreport.smtp
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
    printp "Now please describe the bug in more detail [Finish pressing ESC]:"
    read -d $'\e' longDescription

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

        debugStatement "tar file path: $tarFilePath\n
                        Address report was sent from: $sender\n
                        Address report will be sent to: $destination"

        while [ $count = 1 ];
        do
            ( echo open $smtpServer 25
              sleep 5
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
    local url
    local tarfile

    url=$1
    tarfile=$2

    echo "***************************************************************"
    if [ -f "$tarfile" ]; then
        echo "* You can find the file with all the information here:"
        echo "*"
        echo "*\t$tarfile"
        echo "*"
    fi
    if [ ! -z "$url" ]; then
        echo "*"
        echo "* The report tar file has been stored on our bugreport SE:\n"
        echo "*\t$url"
    fi
    echo "*"
    echo "* Please send an e-mail to"
    echo "*"
    echo "*\t$supportEmail"
    echo "*"
    echo "* and write a short description of the bug in the subject line and the long"
    echo "* description in the body of the e-mail. Also provide the bugreport SE URL
    echo "* from above and
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
    local domainChoice
    local allDomains
    local commandSummary

    supportEmail=$(getProperty dcache.submit.bugreport.supporter.email)
    commandsToExecute=$(getProperty dcache.submit.bugreport.commands)
    files=$(getProperty dcache.submit.bugreport.paths)
    tmpReportPath=$(getProperty dcache.submit.bugreport.tmpfilepath)
    timeStamp=$(date +'%Y-%m-%dT%H:%M:%SUTC')
    tmpReportPath=$tmpReportPath/$timeStamp
    tmpReportfile=$tmpReportPath/bugReportFile.tmp
    heapdumpFileName=$(getProperty dcache.submit.bugreport.heapdumpfile.name)
    tmpHeapdumpFile=$tmpReportPath/$heapdumpFileName
    FQSN="$(getProperty dcache.submit.bugreport.se.name):$(getProperty dcache.submit.bugreport.se.port)$(getProperty dcache.submit.bugreport.se.path)"
    smtpServer=$(getProperty dcache.submit.bugreport.smtp)
    senderMailAddress=$(getProperty dcache.submit.bugreport.reporter.email)
    domainChoice=""
    allDomains=""

    if [ "$(uname)" = "SunOS" ]; then
        echo "Bug reporting not implemented yet. Ask Christian to do that if needed."  1>&2;
    fi

    if [ $# -ne 0 ]; then

        command="$1"
        shift
        filesFromCommandLine="$@"

        debugStatement "Command added: $command\n
                        Files added as parameters: $filesFromCommandLine"

        case "$command" in
            "add")
            debugStatement "Command add"
            files="$files $filesFromCommandLine"
            ;;
            "only")
            debugStatement "Command only"
            files=$filesFromCommandLine
            ;;
            *)
            usage
        esac
    fi

    commandSummary=$(while IFS= read -r line;
    do
        commandDesc=$(expr "${line}" : "\(.*\)::.*$")
        commandDesc=$(echo $commandDesc | sed 's/^ *//')
        command=$(expr "${line}" : ".*::\(.*$\)")
        echo "\t- $commandDesc: $command"
    done <<<"$commandsToExecute")

    echo ""
    echo "Submitting Bug Report"
    echo "***********************************************"
    echo ""
    echo "The following information will be included in this bug report:"
    echo "$commandSummary"
    echo ""
    echo "and these files and directories:"
    for reportPath in $files; do
        echo "\t- $reportPath"
    done
    echo ""
    echo "If you like to provide all the above stated information in this report enter 'y'."
    echo "Enter 'n' to manually select which files and directories to add to this bug"
    echo "report."
    choice=$(checkForCorrectYesOrNoAnswer)

    # Create basic information that will be included in any report
    createBasicBugReportFile "$tmpReportfile" "$tmpReportPath" "$commandsToExecute"

    if [ "$choice" = "n" ]; then
        printp " You have chosen to select the information provided with this report
                 piece by piece."
        for pieceOfInfo in $files; do

            debugStatement "PieceOfInfo: $pieceOfInfo\n
                            TmpReportFile: $tmpReportfile\n
                            Content header: $pieceOfInfo file\n
                            Index: $index"

            addItemToBugReport $pieceOfInfo $tmpReportfile $index
         done
         debugStatement "System editor: $EDITOR"
         printp "Please check the following file content. By saving the file you give your
                consent to send everything that is in the file along with your bug report. Press RETURN to continue:"
         read

         which vi > /dev/null
         viPresent=$?
         which emacs  > /dev/null
         emacsPresent=$?
         which nano  > /dev/null
         nanoPresent=$?
         if [ $viPresent ]; then
           `which vi` $tmpReportfile
         else
             if [ $emacsPresent ]; then
                `which emacs` $tmpReportfile
             else
                if [ $nanoPresent ]; then
                    `which nano` $tmpReportfile
                else
                    echo "No editor was found, please provide the path to your editor:"
                    read editorPath
                    $editorPath $tmpReportfile
                fi
             fi
         fi
    else

        debugStatement "Adding everything to the report\n
                        Files are: $files"

        for pieceOfInfo in $files; do

            debugStatement "PieceOfInfo: $pieceOfInfo"

            if [ -d $pieceOfInfo ]; then
                filesInDirectory=$(ls $pieceOfInfo)
                for file in $filesInDirectory; do

                    debugStatement "Adding File in directory $pieceOfInfo: $file"

                    addFile $pieceOfInfo/$file $tmpReportfile $index
                    addEntryToTableOfContent $tmpReportfile $index $file
                    echo "File added: $pieceOfInfo/$file"
                    index=$(($index + 1))
                done
            else

                debugStatement "Adding single file: $pieceOfInfo"

                addFile $pieceOfInfo $tmpReportfile "$pieceOfInfo file" $index
                addEntryToTableOfContent $tmpReportfile $index $pieceOfInfo
                echo "File added: $pieceOfInfo"
                index=$(($index + 1))
            fi
        done

        printp "Everything will be sent with the report. Please check the following file content.
        By saving the file you give your consent to send everything that is in the file
        along with your bug report.
        Press RETURN to continue:"
        read
        if [ $EDITOR ]; then
           $EDITOR $tmpReportfile
        else
           vi $tmpReportfile
        fi
    fi

    echo "Include heap dump y/n:"
    yesOrNo=$(checkForCorrectYesOrNoAnswer)
    allDomains=$(getProperty dcache.domains)
    if [ $yesOrNo = "y" ]; then
        echo "These are the domains on your machine:"
        echo $allDomains
        echo
        while [[ $(echo "$allDomains" | grep -c "$domainChoice") -eq 0 || -z "$domainChoice" ]]; do
            debugStatement "$domainChoice not in \"$allDomains\"\n
                            Result was: $(echo "$allDomains" | grep -c "$domainChoice")"
            echo "Please provide a space separated list of domains, which will be included in the dump:"
            read domainChoice
        done

        debugStatement "Calling addHeapDump with parameters:\n
                        $tmpReportfile\n
                        $domainChoice\n
                        $tmpHeapdumpFile"

        addHeapDump "$tmpReportfile" "$domainChoice" "$tmpHeapdumpFile"
    fi

    # Sending bugreport to support@dcache.org

    printp "Packing file $tmpReportfile"
    tarFile="$tmpReportPath.tar.gz"
    tar czf $tarFile -C "$tmpReportPath" . > /dev/null

    echo "Deleting tmp bug report directory: $tmpReportPath"
    if [ $tmpReportPath != "/" ]; then
        rm -rf $tmpReportPath
    fi

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
        echo "3 Please enter y thread yes or n for no:"
        echo "You entered:" $sendDirectByMail
        read sendDirectByMail
    done
    checkedMail="Mail not checked yet"
    if [ "$sendDirectByMail" = "y" ]; then
        while [ -z "$senderMailAddress" ] && [ "$senderMailAddress" != "$checkedMail" ]
        do
                debugStatement "sendMail check loop"

                if [ -z "$senderMailAddress" ]; then
                    printp "You have not specified an reporter e-mail address, please
                            set the dcache.submit.bugreport.reporter.email
                            property in your $(getProperty dcache.paths.setup) file
                            or enter the sender mail address here and press <return>:"
                    read senderMailAddress
                fi

                debugStatement "Checking reporter mail address: $senderMailAddress"

                checkedMail=$(echo "$senderMailAddress" | grep '^[A-z0-9\._%+-]+@[A-z0-9\.-]+\.[A-z]{2,4}$' || :)

                debugStatement "After check sendermail\n
                                checkedMail is: $checkedMail\n
                                senderMailAddress: $senderMailAddress"

                if [ "$senderMailAddress" != "$checkedMail" ]; then
                    printp "Please check your e-mail format. You entered: $senderMailAddress. Please reenter the
                    a correctly formated e-mail address:"
                    read senderMailAddress
                else
                    printp "The bug report will be sent using $senderMailAddress."
                fi
        done

        debugStatement "Reporter e-mail set to: $senderMailAddress and checkedMail: $checkedMail"

        sendBugReportMail  "$senderMailAddress" "$supportEmail" "$url" "$tarFile"
        rm "$tarFile"
    else
        showFinalReportMessage $url $tarFile
    fi
}
