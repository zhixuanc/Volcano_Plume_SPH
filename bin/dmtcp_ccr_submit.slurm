#!/bin/bash
#SBATCH --time=71:30:00
#SBATCH --nodes=32
#SBATCH --cpus-per-task=1
#SBATCH --tasks-per-node=1
#SBATCH --mem=12000
#SBATCH --mail-user=zhixuanc@buffalo.edu
#SBATCH --mail-type=ALL
#SBATCH --job-name=fine_resolution
#SBATCH --output=output.out
#SBATCH --error=output.err
#SBATCH --partition=general-compute

# spit out some basic SLURM information
echo "SLURM_JOBID         = "$SLURM_JOB_ID
echo "SLURM_SUBMIT_DIR    = "$SLURM_SUBMIT_DIR
echo "SLURM_NODELIST      = "`nodeset -e $SLURM_NODELIST`
echo "SLURM_NPROCS        = "$SLURM_NPROCS
echo "SLURM_NNODES        = "$SLURM_NNODES
echo "SLURM_CPUS_PER_TASK = "$SLURM_CPUS_PER_TASK
echo "SLURMTMPDIR         = "$SLURMTMPDIR 

#because CCR is not finish updating yet, I need the following line to make the excutable file works properly.
export HDF5_DISABLE_VERSION_CHECK=1

module load dmtcp
#module load openmpi/gcc-4.4.7/1.8.0
#module load openmpi/gcc-4.4.6/1.6.5
module load intel-mpi/5.0.2
#module load openmpi/gcc-4.4.6/1.6.5
module load hdf
module list
ulimit -s unlimited

#
# How long to run the application before checkpointing.
# After checkpointing, the application will be shut down. 
# Users will typically want to set this to occur a bit before 
# the job's walltime expires.
#
CHECKPOINT_TIME=71h

# EXE is the name of the application/executable
# ARGS is any command-line args
# OUTFILE is the file where stdout will be redirected
# ERRFILE if the file where stderr will be redirected
EXE=$SLURM_SUBMIT_DIR/particler
#ARGS="1200000000 0 8"
ARGS="-n 4"
OUTFILE=sml100.out
ERRFILE=sml100.err

# This script with auto-sense whether to perform a checkpoint
# or restart operation. Set FORCE_CHECKPOINT to yes if you 
# DO NOT want to restart even if a restart script is located 
# in the working directory.
FORCE_CHECKPOINT=No

# *************************************************************************************************
# *************************************************************************************************
# Users should not have to change anything beyond this point!
# *************************************************************************************************
# *************************************************************************************************
export DMTCP_TMPDIR=$SLURM_SUBMIT_DIR

# configure openmpi environment to use tcp   --> I'd like to use infiniband
export OMPI_MCA_mtl=^psm
export OMPI_MCA_btl=self,tcp


export I_MPI_PMI_LIBRARY=/usr/lib64/libpmi.so
export I_MPI_FABRICS_LIST=tcp

# =================================================================================================
# start_coordinator() 
#   Routine provided by Artem Polyakov
#
# Start dmtcp coordinator on launching node. Free TCP port is automatically allocated.
# this function creates dmtcp_command.$JOBID script that serves like a wrapper around
# dmtcp_command that tunes it on exact dmtcp_coordinator (it's hostname and port)
# instead of typing "dmtcp_command -h <coordinator hostname> -p <coordinator port> <command>"
# you just type "dmtcp_command.$JOBID <command>" and talk to coordinator of JOBID job
# =================================================================================================
start_coordinator()
{
    fname=dmtcp_command.$SLURM_JOBID
    h=`hostname`
    echo "dmtcp_coordinator --daemon --exit-on-last -p 0 --port-file $fname $@ 1>/dev/null 2>&1"
    dmtcp_coordinator --daemon --exit-on-last -p 0 --port-file $fname $@ 1>/dev/null 2>&1
    
    while true; do 
        if [ -f "$fname" ]; then
            p=`cat $fname`
            if [ -n "$p" ]; then
                # try to communicate ? dmtcp_command -p $p l
                break
            fi
        fi
    done
    
    # Create dmtcp_command wrapper for easy communication with coordinator
    p=`cat $fname`
    chmod +x $fname
    echo "#!/bin/bash" > $fname
    echo >> $fname
    echo "export PATH=$PATH" >> $fname
    echo "export DMTCP_HOST=$h" >> $fname
   # echo "export DMTCP_COORD_PORT=$p" >> $fname
    echo "export DMTCP_PORT=$p" >> $fname
    echo "dmtcp_command \$@" >> $fname

    # Setup local environment for DMTCP
   # export DMTCP_COORD_HOST=$h
   # export DMTCP_COORD_PORT=$p
   
    export DMTCP_HOST=$h
    export DMTCP_PORT=$p
}

echo "Launching dmtcp coordintor daemon"
echo "start_coordinator --exit-after-ckpt"
start_coordinator --exit-after-ckpt

# convert checkpoint time to seconds
nTics=`echo $CHECKPOINT_TIME | \
sed 's/m/ \* 60/g' | \
sed 's/h/ \* 3600/g' | \
sed 's/d/ \* 86400/g' | \
sed 's/s//g' | \
bc | \
awk '{ printf("%d\n", $1); }'`
echo "Checkpointing will commence after $nTics seconds"

tic=`date +%s`
if [[ -f ./dmtcp_restart_script.sh ]] && [[ "${FORCE_CHECKPOINT}" == "No" ]]; then
  echo "Restarting application under dmtcp control"
  echo "./dmtcp_restart_script.sh -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT -i $nTics 1>>$OUTFILE 2>>$ERRFILE"
 # ./dmtcp_restart_script.sh -h $DMTCP_COORD_HOST -p $DMTCP_COORD_PORT -i $nTics 1>>${OUTFILE}.${SLURM_JOB_ID} 2>>${ERRFILE}.${SLURM_JOB_ID}
./dmtcp_restart_script.sh -h $DMTCP_HOST -p $DMTCP_PORT -i $nTics 1>>${OUTFILE}.${SLURM_JOB_ID} 2>>${ERRFILE}.${SLURM_JOB_ID}
  cat ${OUTFILE}.${SLURM_JOB_ID} >> ${OUTFILE}
  rm -f ${OUTFILE}.${SLURM_JOB_ID}
  cat ${ERRFILE}.${SLURM_JOB_ID} >> ${ERRFILE}
  rm -f ${ERRFILE}.${SLURM_JOB_ID}
else
  # clear output and error files
  echo "" > ${OUTFILE}
  echo "" > ${ERRFILE}
  echo "Launching application under dmtcp control"
  echo "dmtcp_launch --quiet --rm -i $nTics mpirun $ARGS $EXE 1>${OUTFILE} 2>${ERRFILE}"
  #dmtcp_launch --quiet --rm -i $nTics $ARGS $EXE 1>${OUTFILE} 2>${ERRFILE}
  #srun dmtcp_launch --rm $EXE $ARGS 1>${OUTFILE} 2>${ERRFILE}
  srun dmtcp_launch --quiet --rm -i $nTics $EXE 1>${OUTFILE} 2>${ERRFILE}
fi
toc=`date +%s`

elapsedTime=`expr $toc - $tic`
overheadTime=`expr $elapsedTime - $nTics`
if [ "$overheadTime" -lt "0" ]; then
  overheadTime=0
  echo "All done - no checkpoint was required."
else
  echo "All done - checkpoint files are listed below:"
  ls -1 *.dmtcp
fi

echo "Elapsed Time = $elapsedTime seconds"
echo "Checkpoint Overhead = $overheadTime seconds"

