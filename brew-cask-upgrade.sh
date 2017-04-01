#!/bin/bash

# http://brew.sh
# http://braumeister.org
# http://caskroom.io
# http://caskroom.io/search



###
### asking password upfront
###

if [[ -e /tmp/run_from_backup_script2 ]] && [[ $(cat /tmp/run_from_backup_script2) == 1 ]]
then
    function delete_tmp_backup_script_fifo2() {
        if [ -e "/tmp/tmp_backup_script_fifo2" ]
        then
            rm "/tmp/tmp_backup_script_fifo2"
        else
            :
        fi
        if [ -e "/tmp/run_from_backup_script2" ]
        then
            rm "/tmp/run_from_backup_script2"
        else
            :
        fi
    }
    unset SUDOPASSWORD
    SUDOPASSWORD=$(cat "/tmp/tmp_backup_script_fifo2" | head -n 1)
    USE_PASSWORD='builtin printf '"$SUDOPASSWORD\n"''
    delete_tmp_backup_script_fifo2
    set +a
else

    # solution 1
    # only working for sudo commands, not for commands that need a password and are run without sudo
    # and only works for specified time
    # asking for the administrator password upfront
    #sudo -v
    # keep-alive: update existing 'sudo' time stamp until script is finished
    #while true; do sudo -n true; sleep 600; kill -0 "$$" || exit; done 2>/dev/null &
    
    # solution 2
    # working for all commands that require the password (use sudo -S for sudo commands)
    # working until script is finished or exited
    
    # function for reading secret string (POSIX compliant)
    enter_password_secret()
    {
        # read -s is not POSIX compliant
        #read -s -p "Password: " SUDOPASSWORD
        #echo ''
        
        # this is POSIX compliant
        # disabling echo, this will prevent showing output
        stty -echo
        # setting up trap to ensure echo is enabled before exiting if the script is terminated while echo is disabled
        trap 'stty echo' EXIT
        # asking for password
        printf "Password: "
        # reading secret
        read -r "$@" SUDOPASSWORD
        # reanabling echo
        stty echo
        trap - EXIT
        # print a newline because the newline entered by the user after entering the passcode is not echoed. This ensures that the next line of output begins at a new line.
        printf "\n"
        # making sure builtin bash commands are used for using the SUDOPASSWORD, this will prevent showing it in ps output
        # has to be part of the function or it wouldn`t be updated during the maximum three tries
        #USE_PASSWORD='builtin echo '"$SUDOPASSWORD"''
        USE_PASSWORD='builtin printf '"$SUDOPASSWORD\n"''
    }
    
    # unset the password if the variable was already set
    unset SUDOPASSWORD
    
    # making sure no variables are exported
    set +a
    
    # asking for the SUDOPASSWORD upfront
    # typing and reading SUDOPASSWORD from command line without displaying it and
    # checking if entered password is the sudo password with a set maximum of tries
    NUMBER_OF_TRIES=0
    MAX_TRIES=3
    while [ "$NUMBER_OF_TRIES" -le "$MAX_TRIES" ]
    do
        NUMBER_OF_TRIES=$((NUMBER_OF_TRIES+1))
        #echo "$NUMBER_OF_TRIES"
        if [ "$NUMBER_OF_TRIES" -le "$MAX_TRIES" ]
        then
            enter_password_secret
            ${USE_PASSWORD} | sudo -k -S echo "" > /dev/null 2>&1
            if [ $? -eq 0 ]
            then 
                break
            else
                echo "Sorry, try again."
            fi
        else
            echo ""$MAX_TRIES" incorrect password attempts"
            exit
        fi
    done
fi

# setting up trap to ensure the SUDOPASSWORD is unset if the script is terminated while it is set
trap 'unset SUDOPASSWORD' EXIT

# replacing sudo command with a function, so all sudo commands of the script do not have to be changed
sudo()
{
    ${USE_PASSWORD} | builtin command sudo -p '' -k -S "$@"
    #${USE_PASSWORD} | builtin command -p sudo -p '' -k -S "$@"
    #${USE_PASSWORD} | builtin exec sudo -p '' -k -S "$@"
}


###
### functions
###

homebrew-update() {
    echo ''
    echo "updating homebrew..."
    brew analytics off 1> /dev/null && brew update 1> /dev/null && brew prune 1> /dev/null && brew doctor 1> /dev/null
    echo 'updating homebrew finished ;)'
}

cleanup-all() {
    echo ''
    echo "cleaning up..."
    #brew cleanup
    #brew cask cleanup
    brew cleanup 1> /dev/null
    brew cask cleanup 1> /dev/null
    echo 'cleaning finished ;)'
}

# upgrading all homebrew formulas
brew_show_updates_parallel() {
    # always use _ instead of - because some sh commands called by parallel would give errors

    echo "listing brew formulas updates..."

    printf '=%.0s' {1..80}
    printf '\n'
    printf "%-35s | %-20s | %-5s\n" "BREW NAME" "LATEST VERSION" "LATEST INSTALLED"
    printf '=%.0s' {1..80}
    printf '\n'
    
    TMP_DIR_BREW=/tmp/brew_updates
    export TMP_DIR_BREW

    if [ -e "$TMP_DIR_BREW" ]
    then
        if [ "$(ls -A $TMP_DIR_BREW/)" ]
        then
            rm "$TMP_DIR_BREW"/*    
        else
            :
        fi
    else
        :
    fi
    mkdir -p "$TMP_DIR_BREW"/
    DATE_LIST_FILE_BREW=$(echo "brew_update"_$(date +%Y-%m-%d_%H-%M-%S).txt)
    export DATE_LIST_FILE_BREW
    touch "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW"

    brew_show_updates_parallel_inside() {
        # always use _ instead of - because some sh commands called by parallel would give errors
        local item="$1"
        local BREW_INFO=$(brew info $item)
        #echo BREW_INFO is $BREW_INFO
        local BREW_NAME=$(echo "$BREW_INFO" | grep -e "$item: .*" | cut -d" " -f1 | sed 's/://g')
        #echo BREW_NAME is $BREW_NAME
        # make sure you have jq installed via brew
        local BREW_REVISION=$(brew info "$item" --json=v1 | jq . | grep revision | grep -o '[0-9]')
        #echo BREW_REVISION is $BREW_REVISION
        if [[ "$BREW_REVISION" == "0" ]]
        then
            local NEW_VERSION=$(echo "$BREW_INFO" | grep -e "$item: .*" | cut -d" " -f3 | sed 's/,//g')
        else
            local NEW_VERSION=$(echo $(echo "$BREW_INFO" | grep -e "$item: .*" | cut -d" " -f3 | sed 's/,//g')_"$BREW_REVISION")
        fi
        #echo NEW_VERSION is $NEW_VERSION
        local IS_CURRENT_VERSION_INSTALLED=$(echo $BREW_INFO | grep -q ".*/Cellar/$item/$NEW_VERSION\s.*" 2>&1 && echo -e '\033[1;32mtrue\033[0m' || echo -e '\033[1;31mfalse\033[0m' )
        #echo IS_CURRENT_VERSION_INSTALLED is $IS_CURRENT_VERSION_INSTALLED
        printf "%-35s | %-20s | %-15s\n" "$item" "$NEW_VERSION" "$IS_CURRENT_VERSION_INSTALLED"
        
        # installing if not up-to-date and not excluded
        if [[ "$IS_CURRENT_VERSION_INSTALLED" == "$(echo -e '\033[1;31mfalse\033[0m')" ]] && [[ ${CASK_EXCLUDES} != *"$BREW_NAME"* ]]
        then
            echo "$BREW_NAME" >> "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW"
        fi
    }
    
    #
    local NUMBER_OF_CORES=$(parallel --number-of-cores)
    local NUMBER_OF_MAX_JOBS=$(echo "$NUMBER_OF_CORES * 1.5" | bc -l)
    #echo $NUMBER_OF_MAX_JOBS
    local NUMBER_OF_MAX_JOBS_ROUNDED=$(awk 'BEGIN { printf("%.0f\n", '"$NUMBER_OF_MAX_JOBS"'); }')
    #echo $NUMBER_OF_MAX_JOBS_ROUNDED
    #
    export -f brew_show_updates_parallel_inside
    #
    parallel --will-cite -P "$NUMBER_OF_MAX_JOBS_ROUNDED" -k brew_show_updates_parallel_inside ::: "$(brew list)"
    wait
        
    echo "listing brew formulas updates finished ;)"
}

brew-show-updates-one-by-one() {
    echo "listing brew formulas updates..."

    printf '=%.0s' {1..80}
    printf '\n'
    printf "%-35s | %-20s | %-5s\n" "BREW NAME" "LATEST VERSION" "LATEST INSTALLED"
    printf '=%.0s' {1..80}
    printf '\n'
    
    TMP_DIR_BREW=/tmp/brew_updates
    if [ -e "$TMP_DIR_BREW" ]
    then
        if [ "$(ls -A $TMP_DIR_BREW/)" ]
        then
            rm "$TMP_DIR_BREW"/*    
        else
            :
        fi
    else
        :
    fi
    mkdir -p "$TMP_DIR_BREW"/
    DATE_LIST_FILE_BREW=$(echo "brew_update"_$(date +%Y-%m-%d_%H-%M-%S).txt)
    touch "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW"

    for item in $(brew list); do
        local BREW_INFO=$(brew info $item)
        #echo BREW_INFO is $BREW_INFO
        local BREW_NAME=$(echo "$BREW_INFO" | grep -e "$item: .*" | cut -d" " -f1 | sed 's/://g')
        #echo BREW_NAME is $BREW_NAME
        # make sure you have jq installed via brew
        local BREW_REVISION=$(brew info "$item" --json=v1 | jq . | grep revision | grep -o '[0-9]')
        #echo BREW_REVISION is $BREW_REVISION
        if [[ "$BREW_REVISION" == "0" ]]
        then
            local NEW_VERSION=$(echo "$BREW_INFO" | grep -e "$item: .*" | cut -d" " -f3 | sed 's/,//g')
        else
            local NEW_VERSION=$(echo $(echo "$BREW_INFO" | grep -e "$item: .*" | cut -d" " -f3 | sed 's/,//g')_"$BREW_REVISION")
        fi
        #echo NEW_VERSION is $NEW_VERSION
        local IS_CURRENT_VERSION_INSTALLED=$(echo $BREW_INFO | grep -q ".*/Cellar/$item/$NEW_VERSION\s.*" 2>&1 && echo -e '\033[1;32mtrue\033[0m' || echo -e '\033[1;31mfalse\033[0m' )
        #echo IS_CURRENT_VERSION_INSTALLED is $IS_CURRENT_VERSION_INSTALLED
        printf "%-35s | %-20s | %-15s\n" "$item" "$NEW_VERSION" "$IS_CURRENT_VERSION_INSTALLED"
        
        # installing if not up-to-date and not excluded
        if [[ "$IS_CURRENT_VERSION_INSTALLED" == "$(echo -e '\033[1;31mfalse\033[0m')" ]] && [[ ${CASK_EXCLUDES} != *"$BREW_NAME"* ]]
        then
            echo "$BREW_NAME" >> "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW"
        fi

        BREW_INFO=""
        NEW_VERSION=""
        IS_CURRENT_VERSION_INSTALLED=""
    done
    
    echo "listing brew formulas updates finished ;)"
}


brew-install-updates() {
    echo "installing brew formulas updates..."
        
    while IFS='' read -r line || [[ -n "$line" ]]
    do
        echo 'updating '"$line"'...'
        ${USE_PASSWORD} | brew upgrade "$line"
        echo 'removing old installed versions of '"$line"'...'
        ${USE_PASSWORD} | brew cleanup "$line"
        echo ''
    done <"$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW"
    
    if [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW") == "" ]]
    then
        echo "no brew formula updates available..."
    else
        echo "installing brew formulas updates finished ;)"
    fi
    # special ffmpeg
    if [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "fdk-aac") != "" ]] || [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "sdl2") != "" ]] || [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "freetype") != "" ]] || [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "libass") != "" ]] || [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "libvorbis") != "" ]] || [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "libvpx") != "" ]] || [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "opus") != "" ]] || [[ $(cat "$TMP_DIR_BREW"/"$DATE_LIST_FILE_BREW" | grep "x265") != "" ]]
    then
        echo "rebuilding ffmpeg due to components updates..."
        ${USE_PASSWORD} | brew reinstall ffmpeg --with-fdk-aac --with-sdl2 --with-freetype --with-libass --with-libvorbis --with-libvpx --with-opus --with-x265
    else
        :
    fi
    
}

# selectively upgrade casks
cask_show_updates_parallel () {
    # always use _ instead of - because some sh commands called by parallel would give errors
    echo "listing casks updates..."

    printf '=%.0s' {1..80}
    printf '\n'
    printf "%-35s | %-20s | %-5s\n" "CASK NAME" "LATEST VERSION" "LATEST INSTALLED"
    printf '=%.0s' {1..80}
    printf '\n'
    
    TMP_DIR_CASK=/tmp/cask_updates
    export TMP_DIR_CASK
    if [ -e "$TMP_DIR_CASK" ]
    then
        if [ "$(ls -A $TMP_DIR_CASK/)" ]
        then
            rm "$TMP_DIR_CASK"/*    
        else
            :
        fi
    else
        :
    fi
    mkdir -p "$TMP_DIR_CASK"/
    DATE_LIST_FILE_CASK=$(echo "casks_update"_$(date +%Y-%m-%d_%H-%M-%S).txt)
    export DATE_LIST_FILE_CASK
    DATE_LIST_FILE_CASK_LATEST=$(echo "casks_update_latest"_$(date +%Y-%m-%d_%H-%M-%S).txt)
    export DATE_LIST_FILE_CASK_LATEST
    touch "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK"
    touch "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK_LATEST"
    
    cask_show_updates_parallel_inside() {
        # always use _ instead of - because some sh commands called by parallel would give errors
        local c="$1"
        local CASK_INFO=$(brew cask info $c)
        local CASK_NAME=$(echo "$c" | cut -d ":" -f1 | xargs)
        #if [[ $(brew cask info $c | tail -1 | grep "(app)") != "" ]]
        #then
        #    APPNAME=$(brew cask info $c | tail -1 | awk '{$(NF--)=""; print}' | sed 's/ *$//')
        #else
        #    APPNAME=$(echo $(brew cask info $c | grep -A 1 "==> Name" | tail -1).app)
        #fi
        #local INSTALLED_VERSION=$(plutil -p "/Applications/$APPNAME/Contents/Info.plist" | grep "CFBundleShortVersionString" | awk '{print $NF}' | sed 's/"//g')
        local NEW_VERSION=$(echo "$CASK_INFO" | grep -e "$CASK_NAME: .*" | cut -d ":" -f2 | sed 's/ *//' )
        local IS_CURRENT_VERSION_INSTALLED=$(echo $CASK_INFO | grep -q ".*/Caskroom/$CASK_NAME/$NEW_VERSION.*" 2>&1 && echo -e '\033[1;32mtrue\033[0m' || echo -e '\033[1;31mfalse\033[0m')

        printf "%-35s | %-20s | %-15s\n" "$CASK_NAME" "$NEW_VERSION" "$IS_CURRENT_VERSION_INSTALLED"
        
        # installing if not up-to-date and not excluded
        if [[ "$IS_CURRENT_VERSION_INSTALLED" == "$(echo -e '\033[1;31mfalse\033[0m')" ]] && [[ ${CASK_EXCLUDES} != *"$CASK_NAME"* ]]
        then
            echo "$CASK_NAME" >> "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK"
        fi
        
        if [[ "$NEW_VERSION" == "latest" ]] && [[ ${CASK_EXCLUDES} != *"$CASK_NAME"* ]]
        then
            echo "$CASK_NAME" >> "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK_LATEST"
        fi
    }
    
    #
    local NUMBER_OF_CORES=$(parallel --number-of-cores)
    local NUMBER_OF_MAX_JOBS=$(echo "$NUMBER_OF_CORES * 1.5" | bc -l)
    #echo $NUMBER_OF_MAX_JOBS
    local NUMBER_OF_MAX_JOBS_ROUNDED=$(awk 'BEGIN { printf("%.0f\n", '"$NUMBER_OF_MAX_JOBS"'); }')
    #echo $NUMBER_OF_MAX_JOBS_ROUNDED
    #
    export -f cask_show_updates_parallel_inside
    #
    parallel --will-cite -P "$NUMBER_OF_MAX_JOBS_ROUNDED" -k cask_show_updates_parallel_inside ::: "$(brew cask list)"
    wait
        
    echo "listing casks updates finished ;)"
    
}

cask-show-updates-one-by-one() {
    echo "listing casks updates..."

    printf '=%.0s' {1..80}
    printf '\n'
    printf "%-35s | %-20s | %-5s\n" "CASK NAME" "LATEST VERSION" "LATEST INSTALLED"
    printf '=%.0s' {1..80}
    printf '\n'
    
    TMP_DIR_CASK=/tmp/cask_updates
    if [ -e "$TMP_DIR_CASK" ]
    then
        if [ "$(ls -A $TMP_DIR_CASK/)" ]
        then
            rm "$TMP_DIR_CASK"/*    
        else
            :
        fi
    else
        :
    fi
    mkdir -p "$TMP_DIR_CASK"/
    DATE_LIST_FILE_CASK=$(echo "casks_update"_$(date +%Y-%m-%d_%H-%M-%S).txt)
    DATE_LIST_FILE_CASK_LATEST=$(echo "casks_update_latest"_$(date +%Y-%m-%d_%H-%M-%S).txt)
    touch "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK"
    touch "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK_LATEST"
    
    for c in $(brew cask list); do
        local CASK_INFO=$(brew cask info $c)
        local CASK_NAME=$(echo "$c" | cut -d ":" -f1 | xargs)
        #if [[ $(brew cask info $c | tail -1 | grep "(app)") != "" ]]
        #then
        #    APPNAME=$(brew cask info $c | tail -1 | awk '{$(NF--)=""; print}' | sed 's/ *$//')
        #else
        #    APPNAME=$(echo $(brew cask info $c | grep -A 1 "==> Name" | tail -1).app)
        #fi
        #local INSTALLED_VERSION=$(plutil -p "/Applications/$APPNAME/Contents/Info.plist" | grep "CFBundleShortVersionString" | awk '{print $NF}' | sed 's/"//g')
        local NEW_VERSION=$(echo "$CASK_INFO" | grep -e "$CASK_NAME: .*" | cut -d ":" -f2 | sed 's/ *//' )
        local IS_CURRENT_VERSION_INSTALLED=$(echo $CASK_INFO | grep -q ".*/Caskroom/$CASK_NAME/$NEW_VERSION.*" 2>&1 && echo -e '\033[1;32mtrue\033[0m' || echo -e '\033[1;31mfalse\033[0m')

        printf "%-35s | %-20s | %-15s\n" "$CASK_NAME" "$NEW_VERSION" "$IS_CURRENT_VERSION_INSTALLED"
        
        # installing if not up-to-date and not excluded
        if [[ "$IS_CURRENT_VERSION_INSTALLED" == "$(echo -e '\033[1;31mfalse\033[0m')" ]] && [[ ${CASK_EXCLUDES} != *"$CASK_NAME"* ]]
        then
            echo "$CASK_NAME" >> "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK"
        fi
        
        if [[ "$NEW_VERSION" == "latest" ]] && [[ ${CASK_EXCLUDES} != *"$CASK_NAME"* ]]
        then
            echo "$CASK_NAME" >> "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK_LATEST"
        fi

        CASK_INFO=""
        NEW_VERSION=""
        IS_CURRENT_VERSION_INSTALLED=""
    done
    
    echo "listing casks updates finished ;)"
}


cask-install-updates() {
    echo "installing casks updates..."
    
    while IFS='' read -r line || [[ -n "$line" ]]
    do
        echo 'updating '"$line"'...'
        sudo -v
        #sudo brew cask uninstall "$line" --force
        #${USE_PASSWORD} | brew cask uninstall "$line" --force
        #sudo brew cask install "$line" --force
        #${USE_PASSWORD} | brew cask install "$line" --force
        ${USE_PASSWORD} | brew cask reinstall "$line" --force
        sudo -k
        echo ''
    done <"$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK"
    
    #read -p 'do you want to update all installed casks that show "latest" as version (y/N)? ' CONT_LATEST
    #CONT_LATEST="N"
    CONT_LATEST="$(echo "$CONT_LATEST" | tr '[:upper:]' '[:lower:]')"    # tolower
	if [[ "$CONT_LATEST" == "y" || "$CONT_LATEST" == "yes" ]]
    then
        echo 'updating all installed casks that show "latest" as version...'
        echo ''
        while IFS='' read -r line || [[ -n "$line" ]]
        do
            echo 'updating '"$line"'...'
            sudo -v
            ${USE_PASSWORD} | brew cask uninstall "$line" --force
            ${USE_PASSWORD} | brew cask install "$line" --force
            sudo -k
            echo ''
        done <"$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK_LATEST"
    else
        echo 'skipping all installed casks that show "latest" as version...'
        #echo ''
    fi

    if [[ $(cat "$TMP_DIR_CASK"/"$DATE_LIST_FILE_CASK") == "" ]]
    then
        echo "no cask updates available..."
    else
        echo "installing casks updates finished ;)"
    fi
    
}

###
### running script
###

echo ''
echo "updating homebrew, formulas and casks..."

echo ''

# trapping script to kill subprocesses when script is stopped
# kill -9 can only be silenced with >/dev/null 2>&1 when wrappt into function
function kill_subprocesses() 
{
# kills subprocesses only
pkill -9 -P $$
}

function kill_main_process() 
{
# kills subprocesses and process itself
exec pkill -9 -P $$
}

function unset_variables() {
    unset SUDOPASSWORD
    unset USE_PASSWORD    
}

#trap "unset SUDOPASSWORD; printf '\n'; echo 'killing subprocesses...'; kill_subprocesses >/dev/null 2>&1; echo 'done'; echo 'killing main process...'; kill_main_process" SIGHUP SIGINT SIGTERM
trap "unset_variables; printf '\n'; kill_subprocesses >/dev/null 2>&1; kill_main_process" SIGHUP SIGINT SIGTERM
# kill main process only if it hangs on regular exit
trap "unset_variables; kill_subprocesses >/dev/null 2>&1; exit; kill_main_process" EXIT
#set -e

# creating directory and adjusting permissions
echo "creating directory..."

if [ ! -d /usr/local ]; then
sudo mkdir /usr/local
fi
#sudo chown -R $USER:staff /usr/local
sudo chown -R $(whoami) /usr/local

# checking if online
echo "checking internet connection..."
ping -c 3 google.com > /dev/null 2>&1
if [ $? -eq 0 ]
then
    echo "we are online, running script..."
    echo ''
    # installing command line tools
    if xcode-select --install 2>&1 | grep installed >/dev/null
    then
      	echo command line tools are installed...
    else
      	echo command line tools are not installed, installing...
      	while ps aux | grep 'Install Command Line Developer Tools.app' | grep -v grep > /dev/null; do sleep 1; done
      	#sudo xcodebuild -license accept
    fi
    
    sudo xcode-select --switch /Library/Developer/CommandLineTools
    
    function command_line_tools_update () {
        # updating command line tools and system
        echo "checking for command line tools update..."
        COMMANDLINETOOLUPDATE=$(softwareupdate --list | grep "^[[:space:]]\{1,\}\*[[:space:]]\{1,\}Command Line Tools")
        if [ "$COMMANDLINETOOLUPDATE" == "" ]
        then
        	echo "no update for command line tools available..."
        else
        	echo "update for command line tools available, updating..."
        	softwareupdate -i --verbose "$(echo "$COMMANDLINETOOLUPDATE" | sed -e 's/^[ \t]*//' | sed 's/^*//' | sed -e 's/^[ \t]*//')"
        fi
        #softwareupdate -i --verbose "$(softwareupdate --list | grep "* Command Line" | sed 's/*//' | sed -e 's/^[ \t]*//')"
    }
    #command_line_tools_update
    
    # checking if all dependencies are installed
    echo ''
    echo "checking dependencies..."
    if [[ $(brew list | grep jq) == '' ]] || [[ $(brew list | grep parallel) == '' ]]
    then
        echo "not all dependencies installed, installing..."
        ${USE_PASSWORD} | brew install jq parallel
    else
        echo "all dependencies installed..."
    fi
    
    # will exclude these apps from updating
    # pass in params to fit your needs
    # use the exact brew/cask name and separate names with a pipe |
    BREW_EXCLUDES="${1:-}"
    CASK_EXCLUDES="${2:-}"
    
    
    sudo()
    {
        ${USE_PASSWORD} | builtin command sudo -p '' -S "$@"
    }
    
    homebrew-update
    echo ''
    brew_show_updates_parallel
    #brew-show-updates-one-by-one
    echo ''
    cask_show_updates_parallel
    #cask-show-updates-one-by-one
    echo ''
    brew-install-updates
    echo ''
    cask-install-updates
    
    cleanup-all
    
    # unsetting variables
    unset TMP_DIR_BREW
    unset TMP_DIR_CASK
    unset DATE_LIST_FILE_BREW
    unset DATE_LIST_FILE_CASK
    unset DATE_LIST_FILE_CASK_LATEST
    
else
    echo "not online, skipping updates..."
fi


# done
echo ''
echo "script done ;)"
echo ''



###
### unsetting password
###

unset_variables

# kill all child and grandchild processes
#ps -o pgid= $$ | grep -o '[0-9]*'
#kill -9 -$(ps -o pgid= $$ | grep -o '[0-9]*')

exit
