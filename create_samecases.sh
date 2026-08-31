#!/usr/bin/env bash

# defining experiment CASE NAME, SRCROOT and ...
compset=NOINYOC # define
res=T62_tn14 #define
i=3 #define
CASENAME=$compset.$res.exp$i #define
SRCROOT=/cluster/work/projects/nn9560k/agu002/NorESM23/ #define
CASEDIR=/cluster/work/projects/nn9560k/agu002/NorESM23/cases/  #define


$SRCROOT/cime/scripts/create_newcase --case $CASEDIR/$CASENAME --compset $compset --res $res --project nn9560k --machine olivia --compiler intel --run-unsupported --user-mods-dir /cluster/work/projects/nn9560k/agu002/NorESM23/cime_config/usermods_dirs/reduced_out_devsim/

cd $CASEDIR/$CASENAME
./xmlchange STOP_N=1
./xmlchange STOP_OPTION=nyears
./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=6:00:00
#./xmlchange RESUBMIT=1

./case.setup
./case.build

#mostly related to fectching data from NIRD to OLIVIA cache if missing
caseroot=`./xmlquery --value CASEROOT`
machdir=`./xmlquery --value MACHDIR`
mach=`./xmlquery --value MACH`
my_var=$(shuf -i 1-10000 -n 1)
#my_var=5706
outfilelist=case-$my_var.filelist
conffile=noresm-$USER-$my_var

cp $machdir/$mach/noresm.conf $caseroot/$conffile.conf

sed -i 's/\(manifest = \).*/\1 '"$caseroot/$outfilelist"'/' $caseroot/$conffile.conf
rm /cluster/cache/conf/noresm-$USER-$my_var.done
rm $caseroot/$outfilelist
$machdir/$mach/filelist.sh  -o $caseroot/$outfilelist $caseroot/Buildconf/*_list
cp $caseroot/$conffile.conf /cluster/cache/conf/

timeout=600
echo "/cluster/cache/conf/noresm-$USER-$my_var.done"
while [ ! -f "/cluster/cache/conf/noresm-$USER-$my_var.done" ] && [ "$timeout" -gt 0 ]; do
    sleep 1
    ((timeout--))
done

if [ -f "/cluster/cache/conf/noresm-$USER-$my_var.done" ]; then
    echo "File exists"
else
    echo "Timed out waiting for file"
    exit 1
fi

./case.submit


