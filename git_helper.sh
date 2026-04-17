#!/bin/zsh

### GIT CYCLE HELPER ###########################################################
PROGRAM_NAME=gch
PROGRAM_PATH=${0:A:h}
################################################################################
### Program to help manage development cycles of repos
### Contains functions to 
### - progress cycle
### - create feature, patch, and pre-alpha branches
################################################################################



################################################################################
### UTILITY / COMMON ###########################################################
################################################################################


# @brief Prints to stderr, instead of stdout.
function error {
    echo "ERROR: $@" 1>&2
}




# @brief Confirms else exits, reading a single character.
# @param $1 string to display as prompt
function confirm {
    read -sk "?$1" 
    echo

    if [[ $REPLY =~ ^[yY]$ ]]; then 
       return 0;
    fi
    echo "invalid confirmation, aborting..."
    exit 202 #called inside functions exclusivly
}




# @brief Creates an empty commit, then tags, used for version tracking.
# @param tag
function tagEmpty {
    tag=$1
    git checkout version
    git commit --allow-empty # USING CONFIGURED MESSAGE TEMPLATE
    git tag $tag
}




# @brief Last tag of current checked out branch.
function getLastTag {
    git describe --tags --abbrev=0
}




# without postfix or prefix   major.minor.patch
function newVersionNumber {
    version_number=$1
    sem_ver_type=$2
    major=$(echo $version_number | cut -d'.' -f1)
    minor=$(echo $version_number | cut -d'.' -f2)
    patch=$(echo $version_number | cut -d'.' -f3)

    if [[ $sem_ver_type = major ]]; then
        echo "$((1 + $major )).0.0"
        return 0
    fi

    if [[ $sem_ver_type = minor ]]; then
        echo "${major}.$((1 + $minor)).0"
        return 0
    fi

    if [[ $sem_ver_type = patch ]]; then
        echo "${major}.${minor}.$((1 + $patch))"
        return 0
    fi

    error "sem_ver_type must be major | minor | patch, was $sem_ver_type"
    exit 1
}




## initialise branches etc...
## tags v-0.0.0 on empty commit
function init {
    git init -b main
    git config set core.commentString //
    git config set core.editor "nvim -f"
    git config set commit.template $PROGRAM_PATH/templates/git-default-msg

    git commit --allow-empty -m "initial empty commit"
    git branch version
    git checkout version
    git tag "v-0.0.0"
}




################################################################################
### CYCLE TRANSITIONS ##########################################################
################################################################################

# @brief Merge a single pre-alpha into version.
# tags the resulting merge commit
# @param sem_ver_type [major | minor | patch]
# @param name of pre-alpha branch to merge
# if no pre-alpha specified, and version is RELEASE, continue
function startAlpha {
    branch_name=$1
    sem_ver_type=$1
    git checkout version

    version=$(getLastTag)

    ## if currently not release, cannot start alpha
    if ! [[ $version =~ "^v-*.*.*$" ]]; then
        error "must not start alpha if last tag in version branch is not release, was $version"
        exit 2
    fi

    #### startAlphaFromBranch()
    if [[ $branch_name =~ "v-*.*.0-pa*" ]]; then
        ## TODO assert branch exists
        version_number=$(echo $branch_name | cut -d'-' -f2)
        confirm "Starting v-$version_number-alpha, merging $branch_name [yY]:"
        git merge $branch_name
        tagEmpty "v-$version_number-alpha" #tag the merge commit
        return 0
    fi

    #### startImmediateAlpha()    
    version_number=$(echo $version | cut -d'-' -f2)
    version_number=$( newVersionNumber $version_number $sem_ver_type )

    confirm "Starting v-$version_number-alpha, skipping pre-alpha, from $version [yY]:"
    tagEmpty "v-$version_number-alpha"
    return 0
}




# @brief Starts beta, either from alpha OR release
function startBeta {
    git checkout version

    version=$(getLastTag)
    version_number=$(echo $version | cut -d'-' -f2)
    
    # startBetaFromAlpha()
    if [[ $version =~ "v-*.*.*-alpha*" ]]; then
        confirm "Starting v-$version_number-beta from $version [yY]:"
        tagEmpty "v-$version_number-beta"
        return 0
    fi
    # startBetaFromRelease() [patch only]
    if [[ $version =~ "^v-*.*.*$" ]]; then
        confirm "Starting beta from release, must be patch version [yY]:"
        version_number=$(newVersionNumber $version_number patch)
        tagEmpty "v-$version_number-beta"
        return 0
    fi
    error "beta cannot be started from $version"
    exit 3
}




# @brief Starts release candidate, exclusivly from beta.
function startCandidate {
    git checkout version
    version=$(getLastTag)
    version_number=$(echo $version | cut -d'-' -f2)
    if [[ $version =~ "v-*.*.*-beta*" ]]; then
        confirm "Starting candidate from $version [yY]:"
        tagEmpty "v-$version_number-rc"
        return 0
    fi
    error "candidate cannot be started from $version"
    exit 4
}




# @brief Releases a candidate version.
function release {
    # check if any commits since last rc tag
    # IF commits, fails and retursn
    ## TODO IMPORTANT tag must be on the LAST commit
    
    git checkout version

    version=$(getLastTag)
    version_number=$(echo $version | cut -d'-' -f2)

    # check if release candidate
    if [[ $version =~ "v-*.*.*-rc*" ]]; then
        confirm "release version v-$version_number from $version"
        
        git tag "v-$version_number" # tag last commit, not new empty

        git checkout main
        git merge version # merge release version onto main
        return 0
    fi
    error "cannot release without candidate, was $version"
    exit 5
}





################################################################################
### branches ###################################################################
################################################################################




# @param sem_ver_type whether pre alpha for major or minor version
function startPreAlpha {
    sem_ver_type=$1

    git checkout version
    version=$(getLastTag)

    # get largest pa number
    branches=$(git branch | grep "\-pa" | cut -d'-' -f3- | sort -V)

    version_number=$(echo $version | cut -d'-'  -f2)
    name="v-$(newVersionNumber $version_number $sem_ver_type)-pa"
    
    pa_number=0
    if [[ -n $branches ]]; then
        largest=$(echo $branches | tail -1)
        pa_number=1
        # increment if existing number
        if [[ $largest =~ "pa-*" ]]; then 
          pa_number=$((1 + $(echo $largest | cut -d'-' -f2)  ))
        fi
        name="$name-$pa_number"
    fi

    git branch $name 
}




# @brief Creates a new feature branch.
# checkout last valid commit for new feature branch
# then create feature branch, if it does not exist
# @param name, MUST be formatted ft-1234
function startFeature {
    name=$1 #example,   ft-1234
    git checkout version

    version=$(getLastTag)
    version_number=$(echo $version | cut -d'-' -f2)

    # check is not patch version
    if ! [[ $version =~ "v-*.*.0*" ]]; then
        error "cannot start feature branch from patch version"
        exit 6
    fi

    # check if not beta or candidate
    if [[ $version =~ "v-*.*.*-beta*" || $version =~ "v-*.*.*-rc*" ]]; then
        error "cannot start feature branch from beta or candidate version"
        exit 7
    fi

    if ! [[ $name =~ "ft-*" ]]; then
        error "not a suitable feature branch name"
        exit 8
    fi
    git branch $name
}




# @brief Creates a new patch branch.
# can be started on any version
# @param name, of the new branch
function startPatch {
    name=$1
    git checkout version
    git branch $name
}


################################################################################
### main #######################################################################
################################################################################
cmd=$1        # first argument must be command
## TODO second argument should be true or false, to determine wether test or decision has occured (ensuring no progress utnil true)
#### this could be provided by another program (automated test etc....)

## assert function exists
cmd_type=$(type $cmd)
if ! [[ $cmd_type = *function* ]]; then
    error "$cmd_type"
    error "$cmd is not a function defined in $PROGRAM_NAME, " 
    exit 123
fi

#params=${@:1} # all other arguments are for the command
$cmd ${@:2}  # call command
