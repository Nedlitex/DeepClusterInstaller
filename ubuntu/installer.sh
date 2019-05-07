#!/usr/bin/env bash

# --------------------------------------------------------------------- Globals

DC_WORKER_APP_FOLDER=/var/lib/dcworker
DC_WORKER_APP_METADIR=$DC_WORKER_APP_FOLDER/meta
DC_WORKER_APP_LOGDIR=$DC_WORKER_APP_FOLDER/log
DC_WORKER_APP_WORKDIR=$DC_WORKER_APP_FOLDER/workdir
DC_WORKER_APP_DATADIR=$DC_WORKER_APP_FOLDER/data
DC_WORKER_APP_SCRIPTDIR=$DC_WORKER_APP_FOLDER/scripts
DC_WORKER_APP_TMP=$DC_WORKER_APP_FOLDER/tmp
DC_WORKER_CONDA_BASE=$DC_WORKER_APP_FOLDER/conda
DC_WORKER_CONDA_ENV_BASE=$DC_WORKER_CONDA_BASE/envs
DC_WORKER_CONDA_BIN=$DC_WORKER_CONDA_BASE/bin
DC_WORKER_CONDA_EXE=$DC_WORKER_CONDA_BIN/conda
DC_WORKER_PACKAGE=dcworker
DC_WORKER_ENV=dcworkerrt
DC_WORKER_ENV_PATH=$DC_WORKER_CONDA_ENV_BASE/$DC_WORKER_ENV
DC_WORKER_PYTHON_VERSION=3.7
DC_WORKER_USER=dcworker
DC_WORKER_USER_ID=9999
DC_WORKER_SERVICE_NAME=dcworkerd
DC_WORKER_SERVICE=/etc/systemd/system/$DC_WORKER_SERVICE_NAME.service
DC_WORKER_RUN_SCRIPT=$DC_WORKER_APP_SCRIPTDIR/dcworker_run.sh
DC_WORKER_CONFIG_FILE=$DC_WORKER_APP_METADIR/config.yaml
DC_WORKER_DEFAULT_SERVER_URL="http://dtf-masterserver-dev.us-west-1.elasticbeanstalk.com"
DC_WORKER_REGISTER_GPU_FILE=$DC_WORKER_APP_METADIR/gpu_register.yaml
DC_SUPPORTED_GPU_DRIVER_MAJOR_VERSION_MINIMUM=396
DC_SUPPORTED_GPU_NAMES=("NVIDIA TITAN V"
                        "NVIDIA TITAN Xp"
                        "NVIDIA TITAN X"
                        "GeForce GTX 1080 Ti"
                        "GeForce GTX 1080"
                        "GeForce GTX 1070"
                        "GeForce GTX 1060"
                        "GeForce GTX 1050"
                        "GeForce GTX TITAN X"
                        "GeForce GTX TITAN Z"
                        "GeForce GTX TITAN Black"
                        "GeForce GTX TITAN"
                        "GeForce GTX 980 Ti"
                        "GeForce GTX 980"
                        "GeForce GTX 970"
                        "GeForce GTX 960"
                        "GeForce GTX 950")

DC_DB_USER_NAME="dcworker_db_user"
DC_DB_NAME="dcworker_db"
DC_DATASET_TABLE_NAME="datasets"
# ------------------------------------------------------------------------ Help

# This routine displays the help message.
Help()
{
    echo "DeepCluster Worker Installer: ./installer.sh [OPTIONS]"
    echo ""
    echo "  Install the DeepCluster Worker Package"
    echo "    ex. sudo ./installer.sh -y"
    echo ""
    echo "Options:"
    echo "    -f : Force install (this will remove any previous installation)"
    echo "    -u : Uninstall the DeepCluster Worker Package"
    echo "    -U : Update the packages"
    echo "    -h : Display this message and exit"
    echo "    -y : Auto select all applicable GPUs. If not specified, installer"
    echo "         will check for each supported GPUs"
    echo "    -n <NUM> : Specify the number of workers to associate with each"
    echo "               GPU (default=1). Must be between 1 to 8"
    echo "    -m : Minimum install mode. Assume presence of most dependencies."
    echo "         Do not use on fresh install."
    echo "    -d <Name> <Path> : Save the dataset at <Path> as <Name> in the"
    echo "                       persisted dataset table."
    echo "    -x : Manually edit the config file."
    echo "    -s <SECRET> : Specify the register token if necessary."
    echo "    -G : Skip checking GPU types."

}

# --------------------------------------------------------------------- YesOrNo

# This routine asks for yes or no
YesOrNo()
{

    while true
    do
        echo "$1 [Y/n]"
        read answer

        if [ "$answer" = "Y" ]; then
            return 1
        fi

        if [ "$answer" = "y" ]; then
            return 1
        fi

        if [ "$answer" = "N" ]; then
            return 0
        fi

        if [ "$answer" = "n" ]; then
            return 0
        fi

        echo "Valid input: [Y/n]"
    done
}

# --------------------------------------------------------------------- Cleanup

Cleanup()
{
    if [ -d "$DC_WORKER_APP_FOLDER" ]; then
        echo "[Cleanup] Remove the app folder..."
        rm -rf $DC_WORKER_APP_FOLDER
    fi

    local dcworker_user_id=$(id -u $DC_WORKER_USER 2>&1)
    if [ "$dcworker_user_id" = "$DC_WORKER_USER_ID" ]; then
        echo "[Cleanup] Remove the DDL Worker User..."
        userdel $DC_WORKER_USER
    fi

    # Clean up postgres
    local psql_version=`psql --version 2> /dev/null`
    if [ ! "$psql_version" = "" ]; then
        echo "[Cleanup] Purge database..."
        local drop_user_cmd="dropuser $DC_DB_USER_NAME"
        sudo su - postgres -c "$drop_user_cmd" 2> /dev/null
        local drop_db_cmd="dropdb $DC_DB_NAME"
        sudo su - postgres -c "$drop_db_cmd" 2> /dev/null
    fi

    # Clean up dcworkerd service
    if [ -f "$DC_WORKER_SERVICE" ]; then
        echo "[Cleanup] Remove DeepCluster Worker Service..."
        systemctl stop $DC_WORKER_SERVICE_NAME 2> /dev/null
        systemctl disable $DC_WORKER_SERVICE_NAME 2> /dev/null
        rm $DC_WORKER_SERVICE 2> /dev/null
        systemctl daemon-reload
        systemctl reset-failed
    fi
}

# --------------------------------------------------------------------- Install

# This stage of the installation checks whether there exists a previous install.
PreInstall()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Check Previous Installation               ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    if [ -d "$DC_WORKER_APP_FOLDER" ]; then
        echo "[Error] DDL Worker has already been installed. Use -f flag to reinstall."
        return 0
    fi

    # If there exists a previous DDL Worker user, clean it up now.
    local dcworker_user_id=$(id -u $DC_WORKER_USER 2>&1)
    if [ "$dcworker_user_id" = "$DC_WORKER_USER_ID" ]; then
        userdel $DC_WORKER_USER
    fi

    local dcworker_user_id=$(id -u $DC_WORKER_USER 2>&1)
    if [ "$dcworker_user_id" = "$DC_WORKER_USER_ID" ]; then
        echo "[Error] DDL Worker User already exists and cannot be removed."
        return 0
    fi

    return 1
}

# This stage of the installation sets up the workdir of the DDL Worker.
Install_SetUpWorkDir()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Setup Work Directory                      ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    # Make an app folder.
    mkdir $DC_WORKER_APP_FOLDER
    if [ ! -d "$DC_WORKER_APP_FOLDER" ]; then
        echo "[Error] Cannot create DDL Worker app folder at $DC_WORKER_APP_FOLDER"
        return 0
    fi

    # Make a tmp folder.
    mkdir $DC_WORKER_APP_TMP
    if [ ! -d "$DC_WORKER_APP_TMP" ]; then
        echo "[Error] Cannot create DDL Worker tmp folder at $DC_WORKER_APP_TMP"
        return 0
    fi

    # Make a meta folder.
    mkdir $DC_WORKER_APP_METADIR
    if [ ! -d "$DC_WORKER_APP_METADIR" ]; then
        echo "[Error] Cannot create DDL Worker meta folder at $DC_WORKER_APP_METADIR"
        return 0
    fi

    # Make a workdir folder.
    mkdir $DC_WORKER_APP_WORKDIR
    if [ ! -d "$DC_WORKER_APP_WORKDIR" ]; then
        echo "[Error] Cannot create DDL Worker workdir at $DC_WORKER_APP_WORKDIR"
        return 0
    fi

    # Make a script folder.
    mkdir $DC_WORKER_APP_SCRIPTDIR
    if [ ! -d "$DC_WORKER_APP_SCRIPTDIR" ]; then
        echo "[Error] Cannot create DDL script folder at $DC_WORKER_APP_SCRIPTDIR"
        return 0
    fi

    # Make a log folder.
    mkdir $DC_WORKER_APP_LOGDIR
    if [ ! -d "$DC_WORKER_APP_LOGDIR" ]; then
        echo "[Error] Cannot create DDL log folder at $DC_WORKER_APP_LOGDIR"
        return 0
    fi

    # Make a data folder.
    mkdir $DC_WORKER_APP_DATADIR
    if [ ! -d "$DC_WORKER_APP_DATADIR" ]; then
        echo "[Error] Cannot create DDL data folder at $DC_WORKER_APP_DATADIR"
        return 0
    fi

    return 1
}

# This stage of the installation verifies the GPU is supported and select which GPUs to use.
Install_SelectGPU()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Select GPU for Register                   ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    echo "List available NVIDIA GPUs..."
    nvidia-smi -L

    echo "register_gpus:" > $DC_WORKER_REGISTER_GPU_FILE

    local gpus_info=`nvidia-smi --query-gpu=index,driver_version,gpu_uuid,gpu_bus_id --format=csv,noheader`
    local gpus=()
    while read -r line; do
        gpus+=("$line")
    done <<< "$gpus_info"
    local total_registered=0
    for gpu in "${gpus[@]}"
    do
        local gpu_info=($(echo $gpu | tr "," "\n"))
        local gpu_info_index=${gpu_info[0]}
        local gpu_info_driver_version=${gpu_info[1]}
        local gpu_info_driver_version_split=($(echo $gpu_info_driver_version | tr "." "\n"))
        local gpu_info_driver_version_major=${gpu_info_driver_version_split[0]}
        local gpu_info_uuid=${gpu_info[2]}
        local gpu_rid=${gpu_info[3]}
        local gpu_info_name=`nvidia-smi --id=$gpu_info_index --query-gpu=name --format=csv,noheader`

        # Only target GPUs with supported driver version.
        local select=0
        nvidia-smi --id=$gpu_info_index
        if [ $SKIP_GPU_TYPE_CHECK -eq 0 ]; then
            if [ $gpu_info_driver_version_major -ge $DC_SUPPORTED_GPU_DRIVER_MAJOR_VERSION_MINIMUM ]; then
                local supported=0
                for supported_gpu_name in "${DC_SUPPORTED_GPU_NAMES[@]}"
                do
                    if [ "$gpu_info_name" = "$supported_gpu_name" ]; then
                        supported=1
                        break
                    fi
                done

                if [ $supported -eq 1 ]; then
                    if [ $YES_MODE -eq 1 ]; then
                        select=1
                    else
                        YesOrNo "Register $gpu_info_name @$gpu_rid?"
                        local status=$?
                        if [ $status -eq 1 ]; then
                            select=1
                        else
                            echo "Skip $gpu_info_name @$gpu_rid!"
                        fi
                    fi
                else
                    echo "Skip unsupported $gpu_info_name @$gpu_rid!"
                fi

            else
                echo "Skip $gpu_info_name @$gpu_rid because its driver version ($gpu_info_driver_version) is too low!"
            fi
        else
            select=1
        fi

        # Create one entry in the register file if this GPU is selected.
        if [ $select -eq 1 ]; then
            echo "Register $gpu_info_name ($gpu_info_uuid) @$gpu_rid!"
            echo "- $gpu_info_uuid" >> $DC_WORKER_REGISTER_GPU_FILE
            ((total_registered++))
        fi
    done

    if [ $total_registered -eq 0 ]; then
        echo "[Error] No valid GPU found. Abort installation."
        return 0
    fi

    return 1
}

# This stage of the installation installs Postgres and create the user, database
# and schema for the DDL worker.
Install_Postgres()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Install PostgreSQL                        ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    if [ $MINIMUM_INSTALL -eq 0 ]; then
        apt-get install -y postgresql postgresql-contrib
        local psql_version=`psql --version 2> /dev/null`
        if [ "$psql_version" = "" ]; then
            echo "[Error] Failed to install Postgres."
            return 0
        fi
    else
        echo "Skip installing Postgres as -m flag is present."
    fi

    echo "Using $psql_version"
    sudo -u postgres createuser $DC_DB_USER_NAME
    sudo -u postgres createdb $DC_DB_NAME
    local DC_user_pwd_cmd="alter user $DC_DB_USER_NAME with encrypted password '$DC_DB_USER_NAME'"
    sudo -u postgres psql -c "$DC_user_pwd_cmd"
    local assign_db_to_user_cmd="grant all privileges on database $DC_DB_NAME to $DC_DB_USER_NAME"
    sudo -u postgres psql -c "$assign_db_to_user_cmd"
    return 1
}

# This stage of the installation sets up miniconda for the DDL Worker environment.
Install_Conda()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Install Conda                             ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    echo "Download Miniconda installer..."
    local conda_download_to="$DC_WORKER_APP_TMP/miniconda.sh"
    wget -O $conda_download_to "https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    if [ ! -f "$conda_download_to" ]; then
        echo "[Error] Failed to download Miniconda installer."
        return 0
    fi

    echo "Install Miniconda to $DC_WORKER_CONDA_BASE"
    bash $conda_download_to -b -p $DC_WORKER_CONDA_BASE
    if [ ! -d "$DC_WORKER_CONDA_ENV_BASE" ]; then
        echo "[Error] Failed to install Miniconda."
        return 0
    fi

    if [ ! -d "$DC_WORKER_CONDA_BIN" ]; then
        echo "[Error] Failed to install Miniconda."
        return 0
    fi

    if [ ! -f "$DC_WORKER_CONDA_EXE" ]; then
        echo "[Error] Failed to install Miniconda."
        return 0
    fi

    local conda_version=`$DC_WORKER_CONDA_EXE --version 2> /dev/null`
    if [ "$conda_version" = "" ]; then
        echo "[Error] Failed to install Miniconda."
        return 0
    fi

    echo "$conda_version installed at $DC_WORKER_CONDA_BASE"
    return 1
}

# This stage of the installation installs the Docker CE.
Install_Docker()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Install Docker                            ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    if [ $MINIMUM_INSTALL -eq 1 ]; then
        echo "Skip installing docker as -m flag is present."
        return 1
    fi

    apt-get update
    apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg-agent \
            software-properties-common

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository \
        "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) \
        stable"

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    # Add root to docker group.
    usermod -aG docker $USER

    # Make sure docker installs correctly.
    local docker_version=`docker --version 2> /dev/null`
    if [ "$docker_version" = "" ]; then
        echo "[Error] Failed to install Docker CE."
        return 0
    fi

    echo "$docker_version installed."
    return 1
}

# This stage of the installation installs the NVIDIA Docker Runtime.
Install_NVRT()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Install Nvidia Docker Runtime             ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    if [ $MINIMUM_INSTALL -eq 1 ]; then
        echo "Skip installing Nvidia Docker Runtime as -m flag is present."
        return 1
    fi

    # Purge old version
    docker volume ls -q -f driver=nvidia-docker | xargs -r -I{} -n1 docker ps -q -a -f volume={} | xargs -r docker rm -f
    apt-get purge -y nvidia-docker

    # Add the package repositories
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
    local distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
        tee /etc/apt/sources.list.d/nvidia-docker.list

    apt-get update

    # Install nvidia-docker2 and reload the Docker daemon configuration
    apt-get install -y nvidia-docker2
    pkill -SIGHUP dockerd
    return 1
}

# This stage of the installation sets up the user account that runs the DDL Worker.
Install_SetUpUser()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Setup DeepCluster Worker user             ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    useradd -s /usr/sbin/nologin -r -M -d $DC_WORKER_APP_FOLDER $DC_WORKER_USER -u $DC_WORKER_USER_ID -c "DDL Worker"
    local dcworker_user_id=$(id -u $DC_WORKER_USER 2>&1)
    if [ ! "$dcworker_user_id" = "$DC_WORKER_USER_ID" ]; then
        echo "[Error] DDL Worker User cannot be created."
        return 0
    fi

    usermod -aG docker $DC_WORKER_USER

    # Make user the owner of the app directories.
    chown -R $DC_WORKER_USER:$DC_WORKER_USER $DC_WORKER_APP_FOLDER
    chmod -R 777 $DC_WORKER_APP_FOLDER
    return 1
}

# This stage of the installation sets up the conda environment and install
# necessary packages.
Install_SetUpEnv()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Setup DeepCluster Worker Env              ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    # Get path to conda env directory.
    local old_path=$PATH
    export PATH="$DC_WORKER_CONDA_BIN:$PATH"

    # Create the runtime environment.
    conda create -y -n $DC_WORKER_ENV pip python=$DC_WORKER_PYTHON_VERSION
    source activate $DC_WORKER_ENV
    pip install $DC_WORKER_PACKAGE --no-cache-dir
    source deactivate

    export PATH=$old_path
    # Check if the setup succeeded.
    if [ ! -d "$DC_WORKER_ENV_PATH" ]; then
        echo "[Error] Failed to create environment."
        return 0
    fi

    return 1
}

# This stage of the installtion makes sure the worker will auto-start on boot.
Install_AutoStartOnBoot()
{

    # Create dcworkerd.service file.
    echo "[Unit]" > $DC_WORKER_SERVICE
    echo "Description=DeepCluster Worker Service" >> $DC_WORKER_SERVICE
    echo "StartLimitIntervalSec=10" >> $DC_WORKER_SERVICE
    echo "StartLimitBurst=5" >> $DC_WORKER_SERVICE
    echo "" >> $DC_WORKER_SERVICE
    echo "[Service]" >> $DC_WORKER_SERVICE
    echo "Type=idle" >> $DC_WORKER_SERVICE
    echo "Restart=always" >> $DC_WORKER_SERVICE
    echo "RestartSec=120" >> $DC_WORKER_SERVICE
    echo "User=$DC_WORKER_USER" >> $DC_WORKER_SERVICE
    echo "ExecStart=/usr/bin/env bash $DC_WORKER_RUN_SCRIPT" >> $DC_WORKER_SERVICE
    echo "" >> $DC_WORKER_SERVICE
    echo "[Install]" >> $DC_WORKER_SERVICE
    echo "WantedBy=multi-user.target" >> $DC_WORKER_SERVICE

    # Create a config file.
    echo "MASTER_SERVER: $DC_WORKER_DEFAULT_SERVER_URL" > $DC_WORKER_CONFIG_FILE

    # Shebang.
    echo "#!/usr/bin/env bash" > $DC_WORKER_RUN_SCRIPT
    # Add Conda to PATH.
    echo "export PATH=\"$DC_WORKER_CONDA_BIN:\$PATH\"" >> $DC_WORKER_RUN_SCRIPT
    # Activate environment and start worker.
    local secret_cmd=""
    if [ ! -z "$SECRET" ]; then
        secret_cmd="--secret=$SECRET"
    fi

    echo "source activate $DC_WORKER_ENV && $DC_WORKER_PACKAGE --appdir=$DC_WORKER_APP_FOLDER --sharing=$NUM_WORKER_PER_GPU --runtime=$DC_WORKER_CONFIG_FILE $secret_cmd" >> $DC_WORKER_RUN_SCRIPT
    if [ ! -f "$DC_WORKER_RUN_SCRIPT" ]; then
        echo "[Error] Failed to create $DC_WORKER_RUN_SCRIPT."
        return 0
    fi

    # Make scripts executable
    chmod +x $DC_WORKER_RUN_SCRIPT

    # If opt to edit config file, pause for edit.
    if [ $MANUAL_EDIT_CONFIG -eq 1 ]; then
        "${EDITOR:-nano}" $DC_WORKER_CONFIG_FILE
    fi

    # Register service to auto start on boot
    systemctl enable $DC_WORKER_SERVICE_NAME

    return 1
}

Install()
{

    # Check install requirements...
    PreInstall
    local status=$?
    if [ $status -eq 0 ]; then
        return 0
    fi

    # Create app folder...
    Install_SetUpWorkDir
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Select GPUs to register...
    Install_SelectGPU
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Install Postgres and create db...
    Install_Postgres
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Install Conda...
    Install_Conda
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Install Docker CE...
    Install_Docker
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Install NV Runtime...
    Install_NVRT
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Create user account...
    Install_SetUpUser
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Set up environment...
    Install_SetUpEnv
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Set auto start on boot...
    Install_AutoStartOnBoot
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    # Delete tmp folder...
    if [ -d "$DC_WORKER_APP_TMP" ]; then
        rm -rf $DC_WORKER_APP_TMP
    fi

    # Finally start dcworkerd
    systemctl start $DC_WORKER_SERVICE_NAME

    echo "[Done]"
    return 1
}

# ------------------------------------------------------------------- Uninstall

Uninstall()
{
    Cleanup
    echo "[Done]"
    return 1
}

# ------------------------------------------------------------------- Reinstall

Reinstall()
{
    Cleanup
    Install
    local status=$?
    if [ $status -eq 0 ]; then
        Cleanup
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------- Update

Update_WorkerEnv()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***            Update DeepCluster Worker Env             ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    # Get path to conda env directory.
    local old_path=$PATH
    export PATH="$DC_WORKER_CONDA_BIN:$PATH"

    # Activate the environment and install the latest dcworker package.
    source activate $DC_WORKER_ENV
    pip install --upgrade $DC_WORKER_PACKAGE --no-cache-dir
    source deactivate

    export PATH=$old_path
    return 1
}

Update()
{

    # Update dcworker package.
    Update_WorkerEnv
    local status=$?
    if [ $status -eq 0 ]; then
        return 0
    fi

    return 1
}

# ---------------------------------------------------------------------- DataSet

SaveDataSet()
{

    echo ""
    echo "************************************************************"
    echo "***                                                      ***"
    echo "***                   Save DataSet                       ***"
    echo "***                                                      ***"
    echo "************************************************************"
    echo ""

    if [ "$DATASET_NAME" = "" ]; then
        echo "[Error] -d flag expects a dataset name."
        return 0
    fi

    if [ "$DATASET_PATH" = "" ]; then
        echo "[Error] -d flag expects a dataset path."
        return 0
    fi

    local dataset_folder=$DC_WORKER_APP_DATADIR/$DATASET_NAME
    if [ -d "$dataset_folder" ]; then
        echo "[Error] Dataset $DATASET_NAME already exists."
        return 0
    fi

    mkdir $dataset_folder
    if [ ! -d "$dataset_folder" ]; then
        echo "[Error] Cannot create dataset folder at $dataset_folder"
        return 0
    fi

    if [ -d "$DATASET_PATH" ]; then
        cp -a $DATASET_PATH/* $dataset_folder/
    elif [ -f "$DATASET_PATH" ]; then
        cp  $DATASET_PATH $dataset_folder/
    else
        echo "[Error] Path $DATASET_PATH does not point to any file or folder."
        rm -rf $dataset_folder
        return 0
    fi

    chmod -R 777 $dataset_folder
    local add_dataset_cmd="INSERT INTO $DC_DATASET_TABLE_NAME (dataset_name, local_path, dataset_persist, dataset_ready, refcount) VALUES ('$DATASET_NAME', '$dataset_folder', '1', '1', '0')"
    sudo -u postgres psql -d $DC_DB_NAME -c "$add_dataset_cmd"
    return 1
}

# ----------------------------------------------------------------------- Entry

# Parse the input argument
POSITIONAL=()
ACTION="install"
YES_MODE=0
DASH_N=0
NUM_WORKER_PER_GPU="1"
MINIMUM_INSTALL=0
DATASET_NAME=""
DATASET_PATH=""
MANUAL_EDIT_CONFIG=0
SECRET=""
SKIP_GPU_TYPE_CHECK=0
while [[ $# -gt 0 ]]
do
KEY="$1"
case $KEY in
    -u)
    ACTION="unintall"
    if [ "$ACTION" = "reinstall" ]; then
        echo "[Error] Already specified -f flag."
        exit 1
    fi

    if [ "$ACTION" = "update" ]; then
        echo "[Error] Already specified -U flag."
        exit 1
    fi

    if [ "$ACTION" = "dataset" ]; then
        echo "[Error] Already specified -d flag."
        exit 1
    fi
    shift # past argument
    ;;
    -h)
    ACTION="help"
    break
    ;;
    -f)
    ACTION="reinstall"
    if [ "$ACTION" = "unintall" ]; then
        echo "[Error] Already specified -u flag."
        exit 1
    fi

    if [ "$ACTION" = "update" ]; then
        echo "[Error] Already specified -U flag."
        exit 1
    fi

    if [ "$ACTION" = "dataset" ]; then
        echo "[Error] Already specified -d flag."
        exit 1
    fi
    shift # past argument
    ;;
    -y)
    YES_MODE=1
    shift
    ;;
    -n)
    DASH_N=1
    NUM_WORKER_PER_GPU="$2"
    shift # past argument
    shift # past value
    ;;
    -m)
    MINIMUM_INSTALL=1
    shift # past argument
    ;;
    -U)
    if [ "$ACTION" = "reinstall" ]; then
        echo "[Error] Already specified -f flag."
        exit 1
    fi

    if [ "$ACTION" = "unintall" ]; then
        echo "[Error] Already specified -u flag."
        exit 1
    fi

    if [ "$ACTION" = "dataset" ]; then
        echo "[Error] Already specified -d flag."
        exit 1
    fi
    ACTION="update"
    shift # past argument
    ;;
    -d)
    if [ "$ACTION" = "unintall" ]; then
        echo "[Error] Already specified -u flag."
        exit 1
    fi

    if [ "$ACTION" = "update" ]; then
        echo "[Error] Already specified -U flag."
        exit 1
    fi

    if [ "$ACTION" = "reinstall" ]; then
        echo "[Error] Already specified -f flag."
        exit 1
    fi
    ACTION="dataset"
    DATASET_NAME=$2
    DATASET_PATH=$3
    shift # past argument
    shift # past value1
    shift # past value2
    ;;
    -x)
    MANUAL_EDIT_CONFIG=1
    shift # past argument
    ;;
    -s)
    SECRET=$2
    shift # past argument
    shift # past value
    ;;
    -G)
    SKIP_GPU_TYPE_CHECK=1
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done

if [ ! "$ACTION" = "help" ]; then
    # Make sure we are running as root
    if ! [ $(id -u) = 0 ]; then
        echo "[Error] The script need to be run as root. (Hint: sudo ./installer.sh -y)"
        exit 1
    fi
fi

# If -n is supplied, check the value of -n to be between 1 and 8.
if [ $DASH_N -eq 1 ]; then
    if [[ $NUM_WORKER_PER_GPU =~ [^1-8] ]]; then
        echo "[Error] -n expects input between 1 to 8."
        exit 1
    fi
fi

case $ACTION in
    "install")
    Install
    ;;
    "unintall")
    Uninstall
    ;;
    "reinstall")
    Reinstall
    ;;
    "update")
    Update
    ;;
    "dataset")
    SaveDataSet
    ;;
    *)
    Help
    ;;
esac