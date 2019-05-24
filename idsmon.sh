#!/bin/sh

#update功能有排除，如果使用就添加filter，如果不需要则保留filter
if [ $# != 2 ] && [ $# != 3 ] && [ $# != 6 ]
then
	echo "三种使用方式，一种是分析及监控部署，一种是性能统计，一种是统计更新用"
	echo "方式一：第一个参数是：省份.主机名，或者省份.系列.主机名；第二个参数是：操作目录，需要将$0 放在操作目录中"
	echo "方式二：前两个参数与方式一相同，第三个参数，参数是 performance"
	echo "方式三：前两个参数与方式一相同，第三个参数是update，第四个参数是要统计更新的库名，第五个参数是一次操作的行数，第六个参数为update的方式（频率限制位，可以选择zhou/yue/nian/buxian，这个控制跑一轮的时间意思就是拼音，建议buxian）"
	exit 1;
fi
dbid=$1
workdir=$2
#这里是处理workdir变量的，无论最后带不带斜杠，都处理成统一不带的
st_xt=`echo $workdir|awk '{print length}'`
let st_xtt=st_xt-1
zuihou=`echo $workdir|awk -v xt=$st_xt '{print substr($1,xt,xt)}'`
if [ X$zuihou = X/ ]
then
	workdir=`echo $workdir|awk -v xtt=$st_xtt '{print substr($1,1,xtt)}'`
fi
DIR=$workdir/fx										#轩辕功能所在目录
fxdatabase=fx                     #轩辕导入数据库
dodir=$workdir/idsmon                         #监控功能脚本工作目录，所有操作均会在这个目录执行
updatedir=$workdir/update
log=$workdir/root.log
TAGLOG=$workdir/taglog.log
#通用时间配置                                    
time=`date +"%Y%m%d%H%M%S"`                      
timenowUTC=`date +%s`                            
dt=`date +"%Y%m%d"`                              
dH=`date +"%Y%m%d%H"`                            
dHonly=`date +"%H"`                              
dMonly=`date +"%M"`                              
dYonly=`date +"%Y"`                              
dM=`date +"%Y%m%d%H%M"`                          
dS=`date +"%Y%m%d%H%M%S"`                        
dSn=`date +"%Y-%m-%d %H:%M:%S"`                  
dN=`date +"%H%M%S.%N"`     
dMonly=`echo $dMonly|sed -r 's/0+([1-9])/\1/g'`                                                   
PWDDIR=`pwd`
XN=0			#如果为0则不启动性能统计
sqlite3flag=1 #如果为0则不启动本机环比功能，基于sqlite
debugrmflag=0 #如果为1，则不删除各种临时文件
alarmlog=$workdir/alarm.log                        #记录所有告警的日志
alarmcode1=00003108401                           #warn告警码，没有对应单独告警码的就先用这个
alarmcode2=00003108402                           #error告警码，没有对应单独告警码的就先用这个
seq_alarmcode=00003108403                        #顺扫告警码
ckpt_alarmcode=00003108404                       #ckpt异常告警
nptotal_alarmcode=00003108406                    #page数告警码，可以单独配置，也可以使用统一告警码
extents_alarmcode=00003108405                    #extent告警码
frag_alarmcode=00003108407                       #分片相关告警
onlinelogbak_alarmcode=00003108408               #零备异常告警码
idxlevel_alarmcode=00003108409                   #索引层数告警码
locks_alarmcode=00003108410                      #总体锁资源告警码
remaindernum=1                                   #rmd分区中的数据行数的阀值
fragdaynum=3                                     #分片必须包含从今天起向后数该值的天数
ckptnum=3                                        #数据库处于ckpt状态多少秒后告警
ckptnumjiange=10                                 #数据库检测ckpt间隔
testflag=0                                       #测试标志位，现网使用时该值必须为0
seq_alarmnum1=5                                  #顺扫第一级，每个周期产生顺扫条数的阀值
seq_alarmrow1=10000                              #顺扫第一级，超过该条数的表才会产生一级告警
seq_alarmnum2=100                                #顺扫第二级，每个周期产生顺扫条数的阀值
seq_alarmrow2=500                                #顺扫第二级，超过该条数的表才会产生一级告警
nptotal_threshold=8000000                        #page数告警阀值
extents_threshold=100                            #extent阀值，每个表超过这个值就告警
reservation=7                                    #临时文件保留时间，临时文件比最终报告更详细，但是更占空间，一天大概500M
reservation_pmon=3
reservation_setx=3
onlinelogtempnum=20000                           #一次获取online.log的日志数量
idxlevel_threshold=4                             #索引层数大于这个就产生告警
locks_threshold1=10000                           #总体锁资源数量，超过这个限制再去查单个表的锁占用
locks_threshold2=10000                           #单个表的锁资源数量
filter=("zxc_zxc_zxc_zxc_$dS")

###以下均不可更改####
XITONGTEMP=`uname`                               
XITONG=`echo $XITONGTEMP|tr '[a-z]' '[A-Z]'`     #系统名称
os=`uname -a|awk '{print $1}'|tr '[a-z]' '[A-Z]'`
host=`hostname`
hostname=`hostname`                              
wai=`whoami`                                     
okday=`date -d "+$fragdaynum days" +"%Y%m%d"`    
jiaobenming=`echo $0|awk -F'/' '{print $NF}'`    
export LC_TIME="POSIX"
if [ $XITONG = LINUX ]
then
	dtempbakdate=`date -d "$reservation day ago" +"%Y%m%d"`
	dpmonbakdate=`date -d "$reservation_pmon day ago" +"%Y%m%d"`
	dsetxbakdate=`date -d "$reservation_setx day ago" +"%Y%m%d"`
	d1dayago=`date -d "1 day ago" +"%Y%m%d"`
fi
seqbaogao=$dodir/seqscan.${dt}.html
errornum=0
if [ $# = 6 ]
then
	DBNAME=$4
	RECORDNUM=$5
	TYPE=$6
	updatetaglog=$updatedir/update.tag
fi
#统一命名规则，表名指sysmaster库中原表名，下面用TabName指代
#所有导出的表，均为$TabName.${dS}.temp
#sqlite用表结构为sqlite3_$TabName，sqlite环比后生成的文件均未sqlite3hb.$TabName.$dS.temp
#分析库中原始数据fx_$TabName，sqlite环比数据为sqlite3hb_$TabName，存储过程环比数据为idshb_$TabName

allinit()
{
	st_xt=`echo $DIR|awk '{print length}'`
	let st_xtt=st_xt-1
	zuihou=`echo $DIR|awk -v xt=$st_xt '{print substr($1,xt,xt)}'`
	if [ $zuihou = / ]
	then
		DIR=`echo $DIR|awk -v xtt=$st_xtt '{print substr($1,1,xtt)}'`
	fi
	
	if [ ! -d $DIR ]
	then
		log4s error "${DIR}不存在，自动建立目录"
		mkdir $DIR
		if [ $? = 0 ]
		then
			log4s info "${DIR}创建成功"
		else
			log4s error "${DIR}创建失败"
			exit 1;
		fi
	fi
	if [ ! -f $DIR/sqlite3table.sql ]
	then
cat <<EOF > $DIR/sqlite3table.sql
create table sqlite3_sysprofile
(
	id                   text,
  dbid                 text,
	timestamp            text,
	utctime              integer,
	name                 text,
	value                integer
);

create table sqlite3_sysvplst
(
	id                   text,
  dbid                 text,
	timestamp            text,
	utctime              integer,
	vpid                 text,
	address              text,
	pid                  text,
	usecs_user           text,
	usecs_sys            text,
	scputimep            text,
	rcputimep            text,
	classes              text,
	classname            text,
	readyqueue           text,
	num_ready            text,
	flags                text,
	next                 text,
	prev                 text,
	semid                text,
	lock                 integer,
	total_semops         integer,
	total_busy_wts       integer,
	total_yields         integer,
	total_spins          integer,
	steal_attempts       integer,
	steal_attempts_suc   integer,
	idle_search          integer,
	idle_search_suc      integer,
	vp_poll_scheds       integer,
	vp_mt_naps           integer,
	vp_cache_size        integer,
	vp_cache_allocs      integer,
	vp_cache_miss        integer,
	vp_cache_frees       integer,
	vp_cache_drain       integer,
	vp_cache_nblocks     integer,
	thread_run           real,
	thread_idle          real,
	thread_poll_idle     real
);
create table sqlite3_syschktab
(
	id                   text,
  dbid                 text,
	timestamp            text,
	utctime              integer,
	address              text,
	chknum               text,
	nxchunk              text,
	pagesize             text,
	fpage                text,
	offset               text,
	chksize              text,
	nfree                text,
	mdsize               text,
	udsize               text,
	udfree               text,
	dbsnum               text,
	overhead             text,
	flags                text,
	namlen               text,
	fname                text,
	reads                integer,
	writes               integer,
	pagesread            integer,
	pageswritten         integer,
	readtime             real,
	writetime            real
);

create table sqlite3_sysptprof
(
	id                   text,
  dbid                 text,
	timestamp            text,
	utctime              integer,
	dbsname              text,
	tabname              text,
	partnum              text,
	lockreqs             integer,
	lockwts              integer,
	deadlks              integer,
	lktouts              integer,
	isreads              integer,
	iswrites             integer,
	isrewrites           integer,
	isdeletes            integer,
	bufreads             integer,
	bufwrites            integer,
	seqscans             integer,
	pagreads             integer,
	pagwrites            integer
);

create table sqlite3_syssessions
(
	id                   text,
  dbid                 text,
	timestamp            text,
	utctime              integer,
	sid                  text,
	username             text,
	uid                  text,
	pid                  text,
	hostname             text,
	tty                  text,
	connected            text,
	feprogram            text,
	pooladdr             text,
	is_wlatch            integer,
	is_wlock             integer,
	is_wbuff             integer,
	is_wckpt             integer,
	is_wlogbuf           integer,
	is_wtrans            integer,
	is_monitor           integer,
	is_incrit            integer,
	state                text
);
create table sqlite3_syssesprof
(
	id                   text,
  dbid                 text,
	timestamp            text,
	utctime              integer,
	sid                  text,
	lockreqs             real,
	locksheld            real,
	lockwts              real,
	deadlks              real,
	lktouts              real,
	logrecs              real,
	isreads              real,
	iswrites             real,
	isrewrites           real,
	isdeletes            real,
	iscommits            real,
	isrollbacks          real,
	longtxs              real,
	bufreads             real,
	bufwrites            real,
	seqscans             real,
	pagreads             real,
	pagwrites            real,
	total_sorts          real,
	dsksorts             real,
	max_sortdiskspace    real,
	logspused            real,
	maxlogsp             real
);
EOF
	fi
	if [ -f $workdir/sqlite3table.db ]
	then
		cp $workdir/sqlite3table.db $DIR/
	fi
	if [ ! -d $dodir ]
	then
		mkdir $dodir
		echo "创建工作目录"
		cp $jiaobenming $dodir
	fi
}
#获取x天之前的主体函数
DOY () 
{
#取系统时间
CURRENTDAY=`date "+%Y-%m-%d"`
BACKYEAR=`echo $CURRENTDAY|awk -F'-' '{print $1}'`
BACKMONTH=`echo $CURRENTDAY|awk -F'-' '{print $2}'`
BACKDAY=`echo $CURRENTDAY|awk -F'-' '{print $3}'`
YEAR=$BACKYEAR

#判断闰年
FYEAR="$YEAR"
 
if [ `expr ${FYEAR} % 400` -eq 0 ];then
    FRUN="366"
else
    if [ `expr ${FYEAR} % 4` -eq 0 ];then
        if [ `expr ${FYEAR} % 100` -eq 0 ];then
            FRUN="365"
        else
            FRUN="366"
        fi
    else
        FRUN="365"
    fi
fi

MONTH=`echo $BACKMONTH | sed 's/^0//g'`
DAY=`echo $BACKDAY | sed 's/^0//g'`
#MD表示
MD=0
#天数累计
MDTOTAL=0
NUM1=$1
	if [ $DAY -gt $NUM1 ]
	then
#超出保留日日期
		DAY=`expr $DAY - $NUM1`
	else
		while [ 1 ]
		do
			MONTH=`expr $MONTH - 1`
			[ $MONTH -le 0 ] && { MONTH=12 ; YEAR=`expr $YEAR - 1` ; }
			case $MONTH in
				1|3|5|7|8|10|12 ) DAYADD=31
					;;
				4|6|9|11 ) DAYADD=30
					;;
				2 )if [ $FRUN = 366 ]
           	then DAYADD=29
						else DAYADD=28
						fi
 
					;;
			esac
 
			DAY=`expr $DAY + $DAYADD`
			[ $DAY -gt $NUM1 ] && { DAY=`expr $DAY - $NUM1` ; break ; }
		done
	fi
	[ $DAY -lt 10 ] && { DAY="0"`expr $DAY` ; }
	[ $MONTH -lt 10 ] && { MONTH="0"`expr $MONTH` ; }
 
	RMDATE="$YEAR-$MONTH-$DAY"
	echo "$RMDATE"
}
getResidueSec()
{
	dMt=`date +"%M"|sed s'/^0//'`
	dSt=`date +"%S"|sed s'/^0//'`
	if [ $dMt -ge 22 ]
	then
		let lMt=60-dMt+22
	else
		let lMt=22-dMt
	fi
	if [ $dSt -ge 22 ]
	then
		let lSt=60-dSt+22
	else
		let lSt=22-dSt
	fi

	
	let residueSec=lMt*60+lSt

	echo $residueSec

}
getResidueMin()
{
	dMt=`date +"%M"|sed s'/^0//'`
	dSt=`date +"%S"|sed s'/^0//'`
	if [ $dMt -gt 22 ]
	then
		let lMt=60-dMt+22
	else
		let lMt=22-dMt
	fi

	echo $lMt

}



log4s()
{
	dStlog4s=`date +"%Y%m%d%H%M%S"`
	echo "$dStlog4s $1 $2" >> $log
	echo "$dStlog4s $1 $2"
	if [ X$1 = Xerror ] || [ X$1 = Xerr ]
	then
		echo "$dStlog4s $2" >> ${log}.error
	fi
}
log4srotate()
{
	log4s info "开始脚本日志备份"
	mv $log $log.$dt
	touch $log
	rm -rf $log.$dtempbakdate
	if [ -f $workdir/cron.log ]
	then
		mv $workdir/cron.log $workdir/cron.log.$dt
		touch $workdir/cron.log
		rm -rf $workdir/cron.log.$dsetxbakdate
	fi
	
}
errornum=0
sendalarm()
{
	#区分告警码，$2位告警码，如果为空，则默认为warn级通用告警
	dStmp=`date +"%Y%m%d%H%M%S"`
	log4s error "$1"
	tempalarmcode=$alarmcode1
	if [ X$2 != X ]
	then
		tempalarmcode=$2
	fi
	echo "$dStmp $tempalarmcode $1" >> $alarmlog
	let errornum=errornum+1
}

Global_Info()
{
	#Global_Info.ENV 每天一次
	log4s info "Global_Info模块开始执行"
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/sysdri.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from sysdri
EOF
	if [ $? = 0 ]
	then
		log4s info "Global_Info.ENV_sysdri操作成功"
	else
		log4s error "Global_Info.ENV_sysdri操作失败" 
	fi
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/sysenv.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from sysenv
EOF
	if [ $? = 0 ]
	then
		log4s info "Global_Info.ENV_sysenv操作成功"
	else
		log4s error "Global_Info.ENV_sysenv操作失败" 
	fi
	#Global Info.Machine Info
	os_nodename=`hostname`
	os_name=`uname -s`
	db_version=`onstat -V |awk '{print $6}'`
	
	if [ $os_name = 'AIX' ]; then
	os_version=`oslevel -r`
	os_kernel_type=`prtconf -k|awk '{print $3}'`
	os_num_procs=`bindprocessor -q|awk '{print NF-4}'`
	os_type_procs=`uname -p`
	os_mem_total=`prtconf -m|awk '{printf "%d", $3/1024+1}'`
	fi
	
	if [ $os_name = 'Linux' ]; then
	os_version=`uname -r`
	os_kernel_type=`uname -p`
	os_num_procs=`cat /proc/cpuinfo|grep proce|wc -l`
	os_type_procs=`uname -p`
	os_mem_total=`cat /proc/meminfo|grep MemTotal|awk '{printf "%d", $2/1024/1024+1}'`
	fi
	
	if [ $os_name = 'HP-UX' ]; then
	os_version=`uname -r`
	os_kernel_type=`uname -m`
	os_num_procs=`machinfo | grep "^[0-9\ ]*logical"|awk '{print $1}'`
	os_type_procs=' '
	os_mem_total=`machinfo |grep Memory|awk '{printf "%d" ,$2/1024+1}'`
	fi
	echo "0|$dbid|$time|$timenowUTC|$os_nodename|$os_name|$os_version|$os_kernel_type|$os_num_procs|$os_type_procs|$os_mem_total|$db_version|" > ${DIR}/machineinfo.${dS}.temp
	
	#Global_Info.Time
	#前两个字段需要统计时才能生成，cnum也是统计统计时间段内的个数
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/sysshmvals.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from sysshmvals;
EOF
	if [ $? = 0 ]
	then
		log4s info "Global_Info.sysshmvals操作成功"
	else
		log4s error "Global_Info.sysshmvals操作失败" 
	fi
	#Global Info.Database Info
	if [ $dbversionBig = 11 ] || [ $dbversionBig = 10 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/sysdatabases.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		name,partnum,owner,created,is_logging,is_buff_log,is_ansi,is_nls,"null",flags
		from sysdatabases
		where name not in ('sysmaster','sysutils','sysadmin','sysuser','onpload','syscdr');
EOF
		if [ $? = 0 ]
		then
			log4s info "Global_Info.database操作成功"
		else
			log4s error "Global_Info.database操作失败" 
		fi
	fi
	if [ $dbversionBig = 12 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/sysdatabases.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		name,partnum,owner,created,is_logging,is_buff_log,is_ansi,is_nls,is_case_insens,flags
		from sysdatabases
		where name not in ('sysmaster','sysutils','sysadmin','sysuser','onpload','syscdr');
EOF
		if [ $? = 0 ]
		then
			log4s  info "Global_Info.database操作成功"
		else
			log4s error "Global_Info.database操作失败" 
		fi
	fi


	cat ${DIR}/sysenv.${dS}.temp        >> ${DIR}/sysenv.${dt}.temp
	cat ${DIR}/sysdatabases.${dS}.temp	>> ${DIR}/sysdatabases.${dt}.temp
	cat ${DIR}/sysdri.${dS}.temp				>> ${DIR}/sysdri.${dt}.temp
	cat ${DIR}/machineinfo.${dS}.temp		>> ${DIR}/machineinfo.${dt}.temp
	cat ${DIR}/sysshmvals.${dS}.temp		>> ${DIR}/sysshmvals.${dt}.temp

}

DB_Profile()
{
	#DB _Profile
	#这个是需要差值的环比类型
	log4s info "DB_Profile模块开始操作"
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/sysprofile.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from sysprofile
EOF
	if [ $? = 0 ]
	then
		log4s info "DB_Profile.IO_Info操作成功"
	else
		log4s error "DB_Profile.IO_Info操作失败" 
	fi
	cat ${DIR}/sysprofile.${dS}.temp			>> ${DIR}/sysprofile.${dt}.temp
}
Memory_Info()
{
	log4s info "Memory_Info模块开始"
	#Memory_Info.Memory_Used_OR_Virtual_Memory_Used
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/syssegments.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from syssegments
EOF
	if [ $? = 0 ]
	then
		log4s info "Memory_Info.Memory_Used_OR_Virtual_Memory_Used操作成功"
	else
		log4s error "Memory_Info.Memory_Used_OR_Virtual_Memory_Used操作失败" 
	fi
	cat ${DIR}/syssegments.${dS}.temp >> ${DIR}/syssegments.${dt}.temp

}
Process_Info()
{
	log4s info "Process_Info模块开始"
	#Process_Info.CPU_VP
	
	if [ $dbversionBig = 10 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/sysvplst.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		vpid,address,pid,usecs_user,usecs_sys,scputimep,rcputimep,
		"null",readyqueue,num_ready,flags,next,prev,semid,lock,"null",
		"null","null","null","null","null","null","null","null","null",
		"null","null","null","null","null","null","null","null","null"
		from sysvplst
EOF
		if [ $? = 0 ]
		then
			log4s info "Process_Info.CPU_VP操作成功"
		else
			log4s error "Process_Info.CPU_VP操作失败" 
		fi
	fi
	if [ $dbversionBig = 11 ] || [ $dbversionBig = 12 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/sysvplst.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		vpid,address,pid,usecs_user,usecs_sys,scputimep,rcputimep,
		class,classname,readyqueue,num_ready,flags,next,prev,semid,
		lock,total_semops,total_busy_wts,total_yields,total_spins,
		steal_attempts,steal_attempts_suc,idle_search,idle_search_suc,
		vp_poll_scheds,vp_mt_naps,vp_cache_size,vp_cache_allocs,
		vp_cache_miss,vp_cache_frees,vp_cache_drain,vp_cache_nblocks,
		thread_run,thread_idle,thread_poll_idle
		from sysvplst
EOF
		if [ $? = 0 ]
		then
			log4s info "Process_Info.CPU_VP操作成功"
		else
			log4s error "Process_Info.CPU_VP操作失败" 
		fi
	fi

	cat ${DIR}/sysvplst.${dS}.temp >> ${DIR}/sysvplst.${dt}.temp
	
	#有用的是classname,busy_secs是usecs_user的和，YIELDS是total_yields的和；thread_run就是本身的和，其中class=soc的值是N/A
}
Disk_Info()
{
	log4s info "Disk_Info模块开始"
	#Disk_Info.CHUNK_IO
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/syschktab.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from syschktab
EOF
	if [ $? = 0 ]
	then
		log4s info "Disk_Info.CHUNK_IO操作成功"
	else
		log4s error "Disk_Info.CHUNK_IO操作失败" 
	fi
	#Disk_Info.Dbspaces_Info
	if [ $dbversionBig = 11 ] || [ $dbversionBig = 10 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/sysdbspaces.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		dbsnum,name,owner,pagesize,fchunk,nchunks,"null","null","null",is_mirrored,is_blobspace,is_sbspace,is_temp,"null",flags
		from sysdbspaces
EOF
		if [ $? = 0 ]
		then
			log4s info "Disk_Info.Dbspaces_Info1操作成功"
		else
			log4s  error "Disk_Info.Dbspaces_Info1操作失败" 
		fi
	fi
	if [ $dbversionBig = 12 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/sysdbspaces.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		dbsnum,name,owner,pagesize,fchunk,nchunks,create_size,extend_size,max_size,is_mirrored,is_blobspace,is_sbspace,is_temp,is_encrypted,flags
		from sysdbspaces
EOF
		if [ $? = 0 ]
		then
			log4s info "Disk_Info.Dbspaces_Info1操作成功"
		else
			log4s error "Disk_Info.Dbspaces_Info1操作失败" 
		fi
	fi
	if [ $dbversionBig = 11 ] || [ $dbversionBig = 10 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/syschunks.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		chknum,dbsnum,nxchknum,pagesize,chksize,offset,nfree,mdsize,
		udsize,udfree,is_offline,is_recovering,is_blobchunk,is_sbchunk,
		is_inconsistent,"null",flags,fname,mfname,moffset,mis_offline,mis_recovering,mflags
		from syschunks;
EOF
		if [ $? = 0 ]
		then
			log4s info "Disk_Info.Dbspaces_Info2操作成功"
		else
			log4s error "Disk_Info.Dbspaces_Info2操作失败" 
		fi
	fi
	if [ $dbversionBig = 12 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/syschunks.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		chknum,dbsnum,nxchknum,pagesize,chksize,offset,nfree,mdsize,
		udsize,udfree,is_offline,is_recovering,is_blobchunk,is_sbchunk,
		is_inconsistent,is_extendable,flags,fname,mfname,moffset,mis_offline,mis_recovering,mflags
		from syschunks;
EOF
		if [ $? = 0 ]
		then
			log4s info "Disk_Info.Dbspaces_Info2操作成功"
		else
			log4s error "Disk_Info.Dbspaces_Info2操作失败" 
		fi
	fi
	cat ${DIR}/syschktab.${dS}.temp			>> ${DIR}/syschktab.${dt}.temp	
	cat ${DIR}/sysdbspaces.${dS}.temp		>> ${DIR}/sysdbspaces.${dt}.temp
	cat ${DIR}/syschunks.${dS}.temp			>> ${DIR}/syschunks.${dt}.temp

}
Table_Info()
{
	log4s info "Table_Info模块开始"
	#首先导出所有库
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/database.unl
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
	name
	from sysdatabases
	where name not in ('sysmaster','sysutils','sysadmin','sysuser','onpload','syscdr');
EOF
	#增删改查操作最多的表和索引
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/sysptprof.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from sysptprof
	where dbsname not in('sysutils','sysadmin','sysuser','onpload','system','sysmaster')
	and tabname not like 'sys%'
	and tabname !='TBLSpace';
EOF
	if [ $? = 0 ]
	then
		log4s info "Table_Info的sysptprof操作成功"
	else
		log4s error "Table_Info的sysptprof操作失败" 
	fi
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/systabinfo.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
	a.*,b.dbsname,b.tabname
	from systabinfo a,systabnames b
	where a.ti_partnum=b.partnum
	and b.dbsname not in('sysutils','sysadmin','sysuser','onpload','system','sysmaster')
	and b.tabname not like 'sys%'
	and b.tabname !='TBLSpace';
EOF
	if [ $? = 0 ]
	then
		log4s info "Table_Info的systabinfo操作成功"
	else
		log4s error "Table_Info的systabinfo失败" 
	fi
	#统计表和索引基本信息
	while read A
	do
		dbtemp=`echo $A|awk -F'|' '{print $5}'`
		dbaccess $dbtemp<<EOF 1>>$log 2>&1
		unload to ${DIR}/sysindexes.$dS.temp.$dbtemp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,"$dbtemp" database,a.*,b.tabname tabname
		from sysindexes a,systables b
		where a.tabid=b.tabid
EOF
		if [ $? = 0 ]
		then
			log4s info "${dbtemp}库的sysindexes表信息操作成功"
		else
			log4s error "${dbtemp}库的sysindexes表信息操作失败" 
		fi
		if [ $dbversionBig = 10 ]
		then
			dbaccess $dbtemp<<EOF 1>>$log 2>&1
			unload to ${DIR}/systables.$dS.temp.$dbtemp
			select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,"$dbtemp" database,
			tabname,owner,partnum,tabid,rowsize,ncols,nindexes,nrows,created,version,
			tabtype,locklevel,npused,fextsize,nextsize,flags,site,dbname,type_xid,am_id,
			"null" pagesize,"null" ustlowts,"null" secpolicyid,"null" protgranularity,"null" statchange,"null" statlevel
			from systables
EOF
			if [ $? = 0 ]
			then
				log4s info "${dbtemp}库的systables表信息操作成功"
			else
				log4s error "${dbtemp}库的systables表信息操作失败" 
			fi
		fi
		if [ $dbversionBig = 11 ]
		then
			dbaccess $dbtemp<<EOF 1>>$log 2>&1
			unload to ${DIR}/systables.$dS.temp.$dbtemp
			select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,"$dbtemp" database,
			tabname,owner,partnum,tabid,rowsize,ncols,nindexes,nrows,created,version,
			tabtype,locklevel,npused,fextsize,nextsize,flags,site,dbname,type_xid,am_id,
			pagesize,ustlowts,secpolicyid,protgranularity,"null" statchange,"null" statlevel
			from systables
EOF
			if [ $? = 0 ]
			then
				log4s info "${dbtemp}库的systables表信息操作成功"
			else
				log4s error "${dbtemp}库的systables表信息操作失败" 
			fi
		fi
		if [ $dbversionBig = 12 ]
		then
			dbaccess $dbtemp<<EOF 1>>$log 2>&1
			unload to ${DIR}/systables.$dS.temp.$dbtemp
			select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,"$dbtemp" database,
			tabname,owner,partnum,tabid,rowsize,ncols,nindexes,nrows,created,version,
			tabtype,locklevel,npused,fextsize,nextsize,flags,site,dbname,type_xid,am_id,
			pagesize,ustlowts,secpolicyid,protgranularity,statchange,statlevel
			from systables
EOF
			if [ $? = 0 ]
			then
				log4s info "${dbtemp}库的systables表信息操作成功"
			else
				log4s error "${dbtemp}库的systables表信息操作失败" 
			fi
		fi
		#下面是导出分片信息
		if [ $dbversionBig = 11 ]
		then
			dbaccess $dbtemp<<EOF 1>>$log 2>&1
			unload to ${DIR}/sysfragments.$dS.temp.$dbtemp
			select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,"$dbtemp" database,
			a.fragtype,a.tabid,a.indexname,a.colno,a.partn,a.strategy,a.location,
			a.servername,a.evalpos,a.exprtext,0,0,a.flags,a.dbspace,a.levels,a.npused,a.nrows,a.clust,
			a.partition,0,0,0,0,b.tabname
			from sysfragments a,systables b
			where a.tabid=b.tabid
EOF
echo "unload to ${DIR}/sysfragments.$dS.temp.$dbtemp"
echo "select 0,'$dbid' dbid,'$time' time,'$timenowUTC' utctime,'$dbtemp' database,"
echo "a.fragtype,a.tabid,a.indexname,a.colno,a.partn,a.strategy,a.location,"
echo "a.servername,a.evalpos,a.exprtext,0,0,a.flags,a.dbspace,a.levels,a.npused,a.nrows,a.clust,"
echo "a.partition,0,0,0,0,b.tabname"
echo "from sysfragments a,systables b"
echo "where a.tabid=b.tabid"
			if [ $? = 0 ]
			then
				log4s info "${dbtemp}库的sysfragments表信息操作成功"
			else
				log4s error "${dbtemp}库的sysfragments表信息操作失败" 
			fi
		fi
		
		if [ $dbversionBig = 12 ]
		then
			dbaccess $dbtemp<<EOF 1>>$log 2>&1
			unload to ${DIR}/sysfragments.$dS.temp.$dbtemp
			select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,"$dbtemp" database,
			a.fragtype,a.tabid,a.indexname,a.colno,a.partn,a.strategy,a.location,
			a.servername,a.evalpos,a.exprtext,0,0,a.flags,a.dbspace,a.levels,a.npused,a.nrows,a.clust,
			a.partition,a.version,a.nupdates,a.ndeletes,a.ninserts,b.tabname
			from sysfragments a,systables b
			where a.tabid=b.tabid
EOF
			if [ $? = 0 ]
				then
					log4s info "${dbtemp}库的sysfragments表信息操作成功"
				else
					log4s error "${dbtemp}库的sysfragments表信息操作失败" 
			fi
		fi
		
		done < ${DIR}/database.unl
		cat ${DIR}/sysindexes.$dS.temp.*       >> ${DIR}/sysindexes.$dt.temp
		cat ${DIR}/sysindexes.$dS.temp.*       >  ${dodir}/sysindex.now
		cat ${DIR}/systables.$dS.temp.*        >> ${DIR}/systables.$dt.temp
		cat ${DIR}/sysptprof.${dS}.temp        >> ${DIR}/sysptprof.${dt}.temp
		cat ${DIR}/sysfragments.${dS}.temp.*   >> ${DIR}/sysfragments.${dt}.temp
		cat ${DIR}/systabinfo.${dS}.temp       >> ${DIR}/systabinfo.${dt}.temp
}
Session_info()
{
	log4s info "Session_info模块开始"
	#由于sid会变化，所以不能用直接环比，需要导入数据库后根据每个sid进行环比
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/syssessions.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from syssessions;
EOF
	if [ $? = 0 ]
	then
		log4s info "syssessions操作成功"
	else
		log4s error "syssessions操作失败" 
	fi
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/syssesprof.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from syssesprof;
EOF
	if [ $? = 0 ]
	then
		log4s info "syssesprof操作成功"
	else
		log4s error "syssesprof操作失败" 
	fi
	cat ${DIR}/syssessions.${dS}.temp >> ${DIR}/syssessions.${dt}.temp
	cat ${DIR}/syssesprof.${dS}.temp 	>> ${DIR}/syssesprof.${dt}.temp

}
Log_info()
{
	log4s info "Log_info模块开始"
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/syslogs.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from syslogs;
EOF
	if [ $? = 0 ]
	then
		log4s info "syslogs操作成功"
	else
		log4s error "syslogs操作失败" 
	fi
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/syslogfil.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from syslogfil;
EOF
	if [ $? = 0 ]
	then
		log4s info "syslogfil操作成功"
	else
		log4s error "syslogfil操作失败" 
	fi
	cat ${DIR}/syslogs.${dS}.temp >> ${DIR}/syslogs.${dt}.temp
	cat ${DIR}/syslogfil.${dS}.temp >> ${DIR}/syslogfil.${dt}.temp
	
}
Config_info()
{
	log4s info "Log_info模块开始"
	dbaccess sysmaster<<EOF 1>>$log 2>&1
	unload to ${DIR}/sysconfig.${dS}.temp
	select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,*
	from sysconfig
EOF
	if [ $? = 0 ]
	then
		log4s info "Config_info操作成功"
	else
		log4s error "Config_info操作失败" 
	fi
	cat ${DIR}/sysconfig.${dS}.temp  >> ${DIR}/sysconfig.${dt}.temp
	
}
SQLHOSTS()
{
	log4s info "SQLHOSTS模块开始"
	if [ $dbversionBig = 10 ]
	then
		cat /ids/etc/sqlhosts|grep -v "^#"|grep -v "demo_on"|sed '/^$/d'|awk  -v dbid=$dbid -v time=$time -v utctime=$timenowUTC -v n="null" -v e='null|' -vOFS='|' '{print dbid,time,utctime,$1,$2,n,n,$3,$4,n,n,n,n,n,n,n,n,n,n,n,e}' > ${DIR}/syssqlhosts.${dS}.temp
		if [ $? = 0 ]
		then
			log4s info "SQLHOSTS操作成功"
		else
			log4s error "SQLHOSTS操作失败" 
		fi
	fi
	if [ $dbversionBig = 11 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/syssqlhosts.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		dbsvrnm,nettype,svrtype,netprot,hostname,svcname,options,
		svrsecurity,clntsecurity,netoptions,netbuf_size,connmux_option,
		svrgroup,endofgroup,redirector,svrid,pamauth,"null"
		from syssqlhosts
EOF
		if [ $? = 0 ]
		then
			log4s info "SQLHOSTS操作成功"
		else
			log4s error "SQLHOSTS操作失败" 
		fi
	fi
	if [ $dbversionBig = 12 ]
	then
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${DIR}/syssqlhosts.${dS}.temp
		select 0,"$dbid" dbid,"$time" time,"$timenowUTC" utctime,
		dbsvrnm,nettype,svrtype,netprot,hostname,svcname,options,
		svrsecurity,clntsecurity,netoptions,netbuf_size,connmux_option,
		svrgroup,endofgroup,redirector,svrid,pamauth,authtoken
		from syssqlhosts
EOF
		if [ $? = 0 ]
		then
			log4s info "SQLHOSTS操作成功"
		else
			log4s error "SQLHOSTS操作失败" 
		fi
	fi

	cat ${DIR}/syssqlhosts.${dS}.temp >> ${DIR}/syssqlhosts.${dt}.temp
	
}



gosqlite3()
{
	echo "$1"|sqlite3 ${workdir}/fx.temp.db
}
xhtml()
{
	echo $1 >> $seqbaogao
}
gohuanbi()
{
	#第一个是表名，要求表名命名规则为master库中原表名，第二个是建立索引的列名，只能一个索引，第三个是最后查询语句
	
	sed 's/.$//' ${DIR}/${1}.${dS}.temp > ${DIR}/${1}.new
	if [ -f ${DIR}/${1}.old ]
	then
		gosqlite3 ".import ${DIR}/${1}.old sqlite3_${1}"
		gosqlite3 ".import ${DIR}/${1}.new sqlite3_${1}"
		gosqlite3 "create index idx_$1 on sqlite3_${1}(${2});"
		gosqlite3 "${3}" > ${DIR}/hb_sqlite3_${1}.${dS}.temp
		if [ $? = 0 ]
		then
			log4s info "$1 sqlite3环比成功"
		else
			log4s error "$1 sqlite3环比失败" 
		fi
		cat ${DIR}/hb_sqlite3_${1}.${dS}.temp >> ${DIR}/hb_sqlite3_${1}.${dt}.temp
		mv ${DIR}/$1.new ${DIR}/$1.old
	else
		mv ${DIR}/${1}.new ${DIR}/${1}.old
	fi
	
	
}
sqlite3huanbi()
{
	dSt=`date +"%Y%m%d%H%M%S"`
	if [ -f $DIR/sqlite3table.db ]
	then
		cp $DIR/sqlite3table.db ${workdir}/fx.temp.db
	elif [ -f $DIR/sqlite3table.sql ]
	then
		
		gosqlite3 ".read $DIR/sqlite3table.sql"
	else
		log4s error "sqlite模块缺失，请退出重新运行"
		exit 1;
	fi
	
	gohuanbi "sysprofile"   "name"      "select b.id,b.dbid,b.timestamp,b.utctime,b.utctime-a.utctime,b.name,case when b.value-a.value >=0 and a.value>=0 and b.value>=0 then b.value-a.value when b.value-a.value >=0 and a.value<0 and b.value<0 then b.value-a.value when b.value-a.value>=0 and a.value<0 and b.value>=0 then b.value else 0 end from sqlite3_sysprofile a,sqlite3_sysprofile b where a.name=b.name and a.utctime<b.utctime;"
	gohuanbi "sysvplst"     "classname" "select b.id,b.dbid,b.timestamp,b.utctime,b.utctime-a.utctime,b.vpid,b.address,b.pid,b.usecs_user,b.usecs_sys,b.scputimep,b.rcputimep,b.classes,b.classname,b.readyqueue,b.num_ready,b.flags,b.next,b.prev,b.semid,case when b.lock-a.lock >=0 and a.lock>=0 and b.lock>=0 then b.lock-a.lock when b.lock-a.lock >=0 and a.lock<0 and b.lock<0 then b.lock-a.lock when b.lock-a.lock>=0 and a.lock<0 and b.lock>=0 then b.lock else 0 end,case when b.total_semops-a.total_semops >=0 and a.total_semops>=0 and b.total_semops>=0 then b.total_semops-a.total_semops when b.total_semops-a.total_semops >=0 and a.total_semops<0 and b.total_semops<0 then b.total_semops-a.total_semops when b.total_semops-a.total_semops>=0 and a.total_semops<0 and b.total_semops>=0 then b.total_semops else 0 end,case when b.total_busy_wts-a.total_busy_wts >=0 and a.total_busy_wts>=0 and b.total_busy_wts>=0 then b.total_busy_wts-a.total_busy_wts when b.total_busy_wts-a.total_busy_wts >=0 and a.total_busy_wts<0 and b.total_busy_wts<0 then b.total_busy_wts-a.total_busy_wts when b.total_busy_wts-a.total_busy_wts>=0 and a.total_busy_wts<0 and b.total_busy_wts>=0 then b.total_busy_wts else 0 end,case when b.total_yields-a.total_yields >=0 and a.total_yields>=0 and b.total_yields>=0 then b.total_yields-a.total_yields when b.total_yields-a.total_yields >=0 and a.total_yields<0 and b.total_yields<0 then b.total_yields-a.total_yields when b.total_yields-a.total_yields>=0 and a.total_yields<0 and b.total_yields>=0 then b.total_yields else 0 end,case when b.total_spins-a.total_spins >=0 and a.total_spins>=0 and b.total_spins>=0 then b.total_spins-a.total_spins when b.total_spins-a.total_spins >=0 and a.total_spins<0 and b.total_spins<0 then b.total_spins-a.total_spins when b.total_spins-a.total_spins>=0 and a.total_spins<0 and b.total_spins>=0 then b.total_spins else 0 end,case when b.steal_attempts-a.steal_attempts >=0 and a.steal_attempts>=0 and b.steal_attempts>=0 then b.steal_attempts-a.steal_attempts when b.steal_attempts-a.steal_attempts >=0 and a.steal_attempts<0 and b.steal_attempts<0 then b.steal_attempts-a.steal_attempts when b.steal_attempts-a.steal_attempts>=0 and a.steal_attempts<0 and b.steal_attempts>=0 then b.steal_attempts else 0 end,case when b.steal_attempts_suc-a.steal_attempts_suc >=0 and a.steal_attempts_suc>=0 and b.steal_attempts_suc>=0 then b.steal_attempts_suc-a.steal_attempts_suc when b.steal_attempts_suc-a.steal_attempts_suc >=0 and a.steal_attempts_suc<0 and b.steal_attempts_suc<0 then b.steal_attempts_suc-a.steal_attempts_suc when b.steal_attempts_suc-a.steal_attempts_suc>=0 and a.steal_attempts_suc<0 and b.steal_attempts_suc>=0 then b.steal_attempts_suc else 0 end,case when b.idle_search-a.idle_search >=0 and a.idle_search>=0 and b.idle_search>=0 then b.idle_search-a.idle_search when b.idle_search-a.idle_search >=0 and a.idle_search<0 and b.idle_search<0 then b.idle_search-a.idle_search when b.idle_search-a.idle_search>=0 and a.idle_search<0 and b.idle_search>=0 then b.idle_search else 0 end,case when b.idle_search_suc-a.idle_search_suc >=0 and a.idle_search_suc>=0 and b.idle_search_suc>=0 then b.idle_search_suc-a.idle_search_suc when b.idle_search_suc-a.idle_search_suc >=0 and a.idle_search_suc<0 and b.idle_search_suc<0 then b.idle_search_suc-a.idle_search_suc when b.idle_search_suc-a.idle_search_suc>=0 and a.idle_search_suc<0 and b.idle_search_suc>=0 then b.idle_search_suc else 0 end,case when b.vp_poll_scheds-a.vp_poll_scheds >=0 and a.vp_poll_scheds>=0 and b.vp_poll_scheds>=0 then b.vp_poll_scheds-a.vp_poll_scheds when b.vp_poll_scheds-a.vp_poll_scheds >=0 and a.vp_poll_scheds<0 and b.vp_poll_scheds<0 then b.vp_poll_scheds-a.vp_poll_scheds when b.vp_poll_scheds-a.vp_poll_scheds>=0 and a.vp_poll_scheds<0 and b.vp_poll_scheds>=0 then b.vp_poll_scheds else 0 end,case when b.vp_mt_naps-a.vp_mt_naps >=0 and a.vp_mt_naps>=0 and b.vp_mt_naps>=0 then b.vp_mt_naps-a.vp_mt_naps when b.vp_mt_naps-a.vp_mt_naps >=0 and a.vp_mt_naps<0 and b.vp_mt_naps<0 then b.vp_mt_naps-a.vp_mt_naps when b.vp_mt_naps-a.vp_mt_naps>=0 and a.vp_mt_naps<0 and b.vp_mt_naps>=0 then b.vp_mt_naps else 0 end,case when b.vp_cache_size-a.vp_cache_size >=0 and a.vp_cache_size>=0 and b.vp_cache_size>=0 then b.vp_cache_size-a.vp_cache_size when b.vp_cache_size-a.vp_cache_size >=0 and a.vp_cache_size<0 and b.vp_cache_size<0 then b.vp_cache_size-a.vp_cache_size when b.vp_cache_size-a.vp_cache_size>=0 and a.vp_cache_size<0 and b.vp_cache_size>=0 then b.vp_cache_size else 0 end,case when b.vp_cache_allocs-a.vp_cache_allocs >=0 and a.vp_cache_allocs>=0 and b.vp_cache_allocs>=0 then b.vp_cache_allocs-a.vp_cache_allocs when b.vp_cache_allocs-a.vp_cache_allocs >=0 and a.vp_cache_allocs<0 and b.vp_cache_allocs<0 then b.vp_cache_allocs-a.vp_cache_allocs when b.vp_cache_allocs-a.vp_cache_allocs>=0 and a.vp_cache_allocs<0 and b.vp_cache_allocs>=0 then b.vp_cache_allocs else 0 end,case when b.vp_cache_miss-a.vp_cache_miss >=0 and a.vp_cache_miss>=0 and b.vp_cache_miss>=0 then b.vp_cache_miss-a.vp_cache_miss when b.vp_cache_miss-a.vp_cache_miss >=0 and a.vp_cache_miss<0 and b.vp_cache_miss<0 then b.vp_cache_miss-a.vp_cache_miss when b.vp_cache_miss-a.vp_cache_miss>=0 and a.vp_cache_miss<0 and b.vp_cache_miss>=0 then b.vp_cache_miss else 0 end,case when b.vp_cache_frees-a.vp_cache_frees >=0 and a.vp_cache_frees>=0 and b.vp_cache_frees>=0 then b.vp_cache_frees-a.vp_cache_frees when b.vp_cache_frees-a.vp_cache_frees >=0 and a.vp_cache_frees<0 and b.vp_cache_frees<0 then b.vp_cache_frees-a.vp_cache_frees when b.vp_cache_frees-a.vp_cache_frees>=0 and a.vp_cache_frees<0 and b.vp_cache_frees>=0 then b.vp_cache_frees else 0 end,case when b.vp_cache_drain-a.vp_cache_drain >=0 and a.vp_cache_drain>=0 and b.vp_cache_drain>=0 then b.vp_cache_drain-a.vp_cache_drain when b.vp_cache_drain-a.vp_cache_drain >=0 and a.vp_cache_drain<0 and b.vp_cache_drain<0 then b.vp_cache_drain-a.vp_cache_drain when b.vp_cache_drain-a.vp_cache_drain>=0 and a.vp_cache_drain<0 and b.vp_cache_drain>=0 then b.vp_cache_drain else 0 end,case when b.vp_cache_nblocks-a.vp_cache_nblocks >=0 and a.vp_cache_nblocks>=0 and b.vp_cache_nblocks>=0 then b.vp_cache_nblocks-a.vp_cache_nblocks when b.vp_cache_nblocks-a.vp_cache_nblocks >=0 and a.vp_cache_nblocks<0 and b.vp_cache_nblocks<0 then b.vp_cache_nblocks-a.vp_cache_nblocks when b.vp_cache_nblocks-a.vp_cache_nblocks>=0 and a.vp_cache_nblocks<0 and b.vp_cache_nblocks>=0 then b.vp_cache_nblocks else 0 end,case when b.thread_run-a.thread_run >=0 and a.thread_run>=0 and b.thread_run>=0 then b.thread_run-a.thread_run when b.thread_run-a.thread_run >=0 and a.thread_run<0 and b.thread_run<0 then b.thread_run-a.thread_run when b.thread_run-a.thread_run>=0 and a.thread_run<0 and b.thread_run>=0 then b.thread_run else 0 end,case when b.thread_idle-a.thread_idle >=0 and a.thread_idle>=0 and b.thread_idle>=0 then b.thread_idle-a.thread_idle when b.thread_idle-a.thread_idle >=0 and a.thread_idle<0 and b.thread_idle<0 then b.thread_idle-a.thread_idle when b.thread_idle-a.thread_idle>=0 and a.thread_idle<0 and b.thread_idle>=0 then b.thread_idle else 0 end,case when b.thread_poll_idle-a.thread_poll_idle >=0 and a.thread_poll_idle>=0 and b.thread_poll_idle>=0 then b.thread_poll_idle-a.thread_poll_idle when b.thread_poll_idle-a.thread_poll_idle >=0 and a.thread_poll_idle<0 and b.thread_poll_idle<0 then b.thread_poll_idle-a.thread_poll_idle when b.thread_poll_idle-a.thread_poll_idle>=0 and a.thread_poll_idle<0 and b.thread_poll_idle>=0 then b.thread_poll_idle else 0 end from sqlite3_sysvplst a,sqlite3_sysvplst b where a.vpid=b.vpid and a.classname=b.classname and a.utctime<b.utctime;"
	gohuanbi "syschktab"    "chknum"    "select b.id,b.dbid,b.timestamp,b.utctime,b.utctime-a.utctime,b.address,b.chknum,b.nxchunk,b.pagesize,b.fpage,b.offset,b.chksize,b.nfree,b.mdsize,b.udsize,b.udfree,b.dbsnum,b.overhead,b.flags,b.namlen,b.fname,case when b.reads-a.reads >=0 and a.reads>=0 and b.reads>=0 then b.reads-a.reads when b.reads-a.reads >=0 and a.reads<0 and b.reads<0 then b.reads-a.reads when b.reads-a.reads>=0 and a.reads<0 and b.reads>=0 then b.reads else 0 end,case when b.writes-a.writes >=0 and a.writes>=0 and b.writes>=0 then b.writes-a.writes when b.writes-a.writes >=0 and a.writes<0 and b.writes<0 then b.writes-a.writes when b.writes-a.writes>=0 and a.writes<0 and b.writes>=0 then b.writes else 0 end,case when b.pagesread-a.pagesread >=0 and a.pagesread>=0 and b.pagesread>=0 then b.pagesread-a.pagesread when b.pagesread-a.pagesread >=0 and a.pagesread<0 and b.pagesread<0 then b.pagesread-a.pagesread when b.pagesread-a.pagesread>=0 and a.pagesread<0 and b.pagesread>=0 then b.pagesread else 0 end,case when b.pageswritten-a.pageswritten >=0 and a.pageswritten>=0 and b.pageswritten>=0 then b.pageswritten-a.pageswritten when b.pageswritten-a.pageswritten >=0 and a.pageswritten<0 and b.pageswritten<0 then b.pageswritten-a.pageswritten when b.pageswritten-a.pageswritten>=0 and a.pageswritten<0 and b.pageswritten>=0 then b.pageswritten else 0 end,case when b.readtime-a.readtime >=0 and a.readtime>=0 and b.readtime>=0 then b.readtime-a.readtime when b.readtime-a.readtime >=0 and a.readtime<0 and b.readtime<0 then b.readtime-a.readtime when b.readtime-a.readtime>=0 and a.readtime<0 and b.readtime>=0 then b.readtime else 0 end,case when b.writetime-a.writetime >=0 and a.writetime>=0 and b.writetime>=0 then b.writetime-a.writetime when b.writetime-a.writetime >=0 and a.writetime<0 and b.writetime<0 then b.writetime-a.writetime when b.writetime-a.writetime>=0 and a.writetime<0 and b.writetime>=0 then b.writetime else 0 end from sqlite3_syschktab a,sqlite3_syschktab b where a.chknum=b.chknum and a.utctime<b.utctime;"
	gohuanbi "sysptprof"    "partnum"   "select b.id,b.dbid,b.timestamp,b.utctime,b.utctime-a.utctime,b.dbsname,b.tabname,b.partnum,case when b.lockreqs-a.lockreqs >=0 and a.lockreqs>=0 and b.lockreqs>=0 then b.lockreqs-a.lockreqs when b.lockreqs-a.lockreqs >=0 and a.lockreqs<0 and b.lockreqs<0 then b.lockreqs-a.lockreqs when b.lockreqs-a.lockreqs>=0 and a.lockreqs<0 and b.lockreqs>=0 then b.lockreqs else 0 end,case when b.lockwts-a.lockwts >=0 and a.lockwts>=0 and b.lockwts>=0 then b.lockwts-a.lockwts when b.lockwts-a.lockwts >=0 and a.lockwts<0 and b.lockwts<0 then b.lockwts-a.lockwts when b.lockwts-a.lockwts>=0 and a.lockwts<0 and b.lockwts>=0 then b.lockwts else 0 end,case when b.deadlks-a.deadlks >=0 and a.deadlks>=0 and b.deadlks>=0 then b.deadlks-a.deadlks when b.deadlks-a.deadlks >=0 and a.deadlks<0 and b.deadlks<0 then b.deadlks-a.deadlks when b.deadlks-a.deadlks>=0 and a.deadlks<0 and b.deadlks>=0 then b.deadlks else 0 end,case when b.lktouts-a.lktouts >=0 and a.lktouts>=0 and b.lktouts>=0 then b.lktouts-a.lktouts when b.lktouts-a.lktouts >=0 and a.lktouts<0 and b.lktouts<0 then b.lktouts-a.lktouts when b.lktouts-a.lktouts>=0 and a.lktouts<0 and b.lktouts>=0 then b.lktouts else 0 end,case when b.isreads-a.isreads >=0 and a.isreads>=0 and b.isreads>=0 then b.isreads-a.isreads when b.isreads-a.isreads >=0 and a.isreads<0 and b.isreads<0 then b.isreads-a.isreads when b.isreads-a.isreads>=0 and a.isreads<0 and b.isreads>=0 then b.isreads else 0 end,case when b.iswrites-a.iswrites >=0 and a.iswrites>=0 and b.iswrites>=0 then b.iswrites-a.iswrites when b.iswrites-a.iswrites >=0 and a.iswrites<0 and b.iswrites<0 then b.iswrites-a.iswrites when b.iswrites-a.iswrites>=0 and a.iswrites<0 and b.iswrites>=0 then b.iswrites else 0 end,case when b.isrewrites-a.isrewrites >=0 and a.isrewrites>=0 and b.isrewrites>=0 then b.isrewrites-a.isrewrites when b.isrewrites-a.isrewrites >=0 and a.isrewrites<0 and b.isrewrites<0 then b.isrewrites-a.isrewrites when b.isrewrites-a.isrewrites>=0 and a.isrewrites<0 and b.isrewrites>=0 then b.isrewrites else 0 end,case when b.isdeletes-a.isdeletes >=0 and a.isdeletes>=0 and b.isdeletes>=0 then b.isdeletes-a.isdeletes when b.isdeletes-a.isdeletes >=0 and a.isdeletes<0 and b.isdeletes<0 then b.isdeletes-a.isdeletes when b.isdeletes-a.isdeletes>=0 and a.isdeletes<0 and b.isdeletes>=0 then b.isdeletes else 0 end,case when b.bufreads-a.bufreads >=0 and a.bufreads>=0 and b.bufreads>=0 then b.bufreads-a.bufreads when b.bufreads-a.bufreads >=0 and a.bufreads<0 and b.bufreads<0 then b.bufreads-a.bufreads when b.bufreads-a.bufreads>=0 and a.bufreads<0 and b.bufreads>=0 then b.bufreads else 0 end,case when b.bufwrites-a.bufwrites >=0 and a.bufwrites>=0 and b.bufwrites>=0 then b.bufwrites-a.bufwrites when b.bufwrites-a.bufwrites >=0 and a.bufwrites<0 and b.bufwrites<0 then b.bufwrites-a.bufwrites when b.bufwrites-a.bufwrites>=0 and a.bufwrites<0 and b.bufwrites>=0 then b.bufwrites else 0 end,case when b.seqscans-a.seqscans >=0 and a.seqscans>=0 and b.seqscans>=0 then b.seqscans-a.seqscans when b.seqscans-a.seqscans >=0 and a.seqscans<0 and b.seqscans<0 then b.seqscans-a.seqscans when b.seqscans-a.seqscans>=0 and a.seqscans<0 and b.seqscans>=0 then b.seqscans else 0 end,case when b.pagreads-a.pagreads >=0 and a.pagreads>=0 and b.pagreads>=0 then b.pagreads-a.pagreads when b.pagreads-a.pagreads >=0 and a.pagreads<0 and b.pagreads<0 then b.pagreads-a.pagreads when b.pagreads-a.pagreads>=0 and a.pagreads<0 and b.pagreads>=0 then b.pagreads else 0 end,case when b.pagwrites-a.pagwrites >=0 and a.pagwrites>=0 and b.pagwrites>=0 then b.pagwrites-a.pagwrites when b.pagwrites-a.pagwrites >=0 and a.pagwrites<0 and b.pagwrites<0 then b.pagwrites-a.pagwrites when b.pagwrites-a.pagwrites>=0 and a.pagwrites<0 and b.pagwrites>=0 then b.pagwrites else 0 end from sqlite3_sysptprof a,sqlite3_sysptprof b where a.partnum=b.partnum and a.utctime<b.utctime;"
	gohuanbi "syssessions"  "sid"       "select b.id,b.dbid,b.timestamp,b.utctime,b.utctime-a.utctime,b.sid,b.username,b.uid,b.pid,b.hostname,b.tty,b.connected,b.feprogram,b.pooladdr,case when b.is_wlatch-a.is_wlatch >=0 and a.is_wlatch>=0 and b.is_wlatch>=0 then b.is_wlatch-a.is_wlatch when b.is_wlatch-a.is_wlatch >=0 and a.is_wlatch<0 and b.is_wlatch<0 then b.is_wlatch-a.is_wlatch when b.is_wlatch-a.is_wlatch>=0 and a.is_wlatch<0 and b.is_wlatch>=0 then b.is_wlatch else 0 end,case when b.is_wlock-a.is_wlock >=0 and a.is_wlock>=0 and b.is_wlock>=0 then b.is_wlock-a.is_wlock when b.is_wlock-a.is_wlock >=0 and a.is_wlock<0 and b.is_wlock<0 then b.is_wlock-a.is_wlock when b.is_wlock-a.is_wlock>=0 and a.is_wlock<0 and b.is_wlock>=0 then b.is_wlock else 0 end,case when b.is_wbuff-a.is_wbuff >=0 and a.is_wbuff>=0 and b.is_wbuff>=0 then b.is_wbuff-a.is_wbuff when b.is_wbuff-a.is_wbuff >=0 and a.is_wbuff<0 and b.is_wbuff<0 then b.is_wbuff-a.is_wbuff when b.is_wbuff-a.is_wbuff>=0 and a.is_wbuff<0 and b.is_wbuff>=0 then b.is_wbuff else 0 end,case when b.is_wckpt-a.is_wckpt >=0 and a.is_wckpt>=0 and b.is_wckpt>=0 then b.is_wckpt-a.is_wckpt when b.is_wckpt-a.is_wckpt >=0 and a.is_wckpt<0 and b.is_wckpt<0 then b.is_wckpt-a.is_wckpt when b.is_wckpt-a.is_wckpt>=0 and a.is_wckpt<0 and b.is_wckpt>=0 then b.is_wckpt else 0 end,case when b.is_wlogbuf-a.is_wlogbuf >=0 and a.is_wlogbuf>=0 and b.is_wlogbuf>=0 then b.is_wlogbuf-a.is_wlogbuf when b.is_wlogbuf-a.is_wlogbuf >=0 and a.is_wlogbuf<0 and b.is_wlogbuf<0 then b.is_wlogbuf-a.is_wlogbuf when b.is_wlogbuf-a.is_wlogbuf>=0 and a.is_wlogbuf<0 and b.is_wlogbuf>=0 then b.is_wlogbuf else 0 end,case when b.is_wtrans-a.is_wtrans >=0 and a.is_wtrans>=0 and b.is_wtrans>=0 then b.is_wtrans-a.is_wtrans when b.is_wtrans-a.is_wtrans >=0 and a.is_wtrans<0 and b.is_wtrans<0 then b.is_wtrans-a.is_wtrans when b.is_wtrans-a.is_wtrans>=0 and a.is_wtrans<0 and b.is_wtrans>=0 then b.is_wtrans else 0 end,case when b.is_monitor-a.is_monitor >=0 and a.is_monitor>=0 and b.is_monitor>=0 then b.is_monitor-a.is_monitor when b.is_monitor-a.is_monitor >=0 and a.is_monitor<0 and b.is_monitor<0 then b.is_monitor-a.is_monitor when b.is_monitor-a.is_monitor>=0 and a.is_monitor<0 and b.is_monitor>=0 then b.is_monitor else 0 end,case when b.is_incrit-a.is_incrit >=0 and a.is_incrit>=0 and b.is_incrit>=0 then b.is_incrit-a.is_incrit when b.is_incrit-a.is_incrit >=0 and a.is_incrit<0 and b.is_incrit<0 then b.is_incrit-a.is_incrit when b.is_incrit-a.is_incrit>=0 and a.is_incrit<0 and b.is_incrit>=0 then b.is_incrit else 0 end,b.state from sqlite3_syssessions a,sqlite3_syssessions b where a.sid=b.sid and a.utctime<b.utctime;"
	gohuanbi "syssesprof"   "sid"       "select b.id,b.dbid,b.timestamp,b.utctime,b.utctime-a.utctime,b.sid,case when b.lockreqs-a.lockreqs >=0 and a.lockreqs>=0 and b.lockreqs>=0 then b.lockreqs-a.lockreqs when b.lockreqs-a.lockreqs >=0 and a.lockreqs<0 and b.lockreqs<0 then b.lockreqs-a.lockreqs when b.lockreqs-a.lockreqs>=0 and a.lockreqs<0 and b.lockreqs>=0 then b.lockreqs else 0 end,case when b.locksheld-a.locksheld >=0 and a.locksheld>=0 and b.locksheld>=0 then b.locksheld-a.locksheld when b.locksheld-a.locksheld >=0 and a.locksheld<0 and b.locksheld<0 then b.locksheld-a.locksheld when b.locksheld-a.locksheld>=0 and a.locksheld<0 and b.locksheld>=0 then b.locksheld else 0 end,case when b.lockwts-a.lockwts >=0 and a.lockwts>=0 and b.lockwts>=0 then b.lockwts-a.lockwts when b.lockwts-a.lockwts >=0 and a.lockwts<0 and b.lockwts<0 then b.lockwts-a.lockwts when b.lockwts-a.lockwts>=0 and a.lockwts<0 and b.lockwts>=0 then b.lockwts else 0 end,case when b.deadlks-a.deadlks >=0 and a.deadlks>=0 and b.deadlks>=0 then b.deadlks-a.deadlks when b.deadlks-a.deadlks >=0 and a.deadlks<0 and b.deadlks<0 then b.deadlks-a.deadlks when b.deadlks-a.deadlks>=0 and a.deadlks<0 and b.deadlks>=0 then b.deadlks else 0 end,case when b.lktouts-a.lktouts >=0 and a.lktouts>=0 and b.lktouts>=0 then b.lktouts-a.lktouts when b.lktouts-a.lktouts >=0 and a.lktouts<0 and b.lktouts<0 then b.lktouts-a.lktouts when b.lktouts-a.lktouts>=0 and a.lktouts<0 and b.lktouts>=0 then b.lktouts else 0 end,case when b.logrecs-a.logrecs >=0 and a.logrecs>=0 and b.logrecs>=0 then b.logrecs-a.logrecs when b.logrecs-a.logrecs >=0 and a.logrecs<0 and b.logrecs<0 then b.logrecs-a.logrecs when b.logrecs-a.logrecs>=0 and a.logrecs<0 and b.logrecs>=0 then b.logrecs else 0 end,case when b.isreads-a.isreads >=0 and a.isreads>=0 and b.isreads>=0 then b.isreads-a.isreads when b.isreads-a.isreads >=0 and a.isreads<0 and b.isreads<0 then b.isreads-a.isreads when b.isreads-a.isreads>=0 and a.isreads<0 and b.isreads>=0 then b.isreads else 0 end,case when b.iswrites-a.iswrites >=0 and a.iswrites>=0 and b.iswrites>=0 then b.iswrites-a.iswrites when b.iswrites-a.iswrites >=0 and a.iswrites<0 and b.iswrites<0 then b.iswrites-a.iswrites when b.iswrites-a.iswrites>=0 and a.iswrites<0 and b.iswrites>=0 then b.iswrites else 0 end,case when b.isrewrites-a.isrewrites >=0 and a.isrewrites>=0 and b.isrewrites>=0 then b.isrewrites-a.isrewrites when b.isrewrites-a.isrewrites >=0 and a.isrewrites<0 and b.isrewrites<0 then b.isrewrites-a.isrewrites when b.isrewrites-a.isrewrites>=0 and a.isrewrites<0 and b.isrewrites>=0 then b.isrewrites else 0 end,case when b.isdeletes-a.isdeletes >=0 and a.isdeletes>=0 and b.isdeletes>=0 then b.isdeletes-a.isdeletes when b.isdeletes-a.isdeletes >=0 and a.isdeletes<0 and b.isdeletes<0 then b.isdeletes-a.isdeletes when b.isdeletes-a.isdeletes>=0 and a.isdeletes<0 and b.isdeletes>=0 then b.isdeletes else 0 end,case when b.isdeletes-a.isdeletes >=0 and a.isdeletes>=0 and b.isdeletes>=0 then b.isdeletes-a.isdeletes when b.isdeletes-a.isdeletes >=0 and a.isdeletes<0 and b.isdeletes<0 then b.isdeletes-a.isdeletes when b.isdeletes-a.isdeletes>=0 and a.isdeletes<0 and b.isdeletes>=0 then b.isdeletes else 0 end,case when b.isrollbacks-a.isrollbacks >=0 and a.isrollbacks>=0 and b.isrollbacks>=0 then b.isrollbacks-a.isrollbacks when b.isrollbacks-a.isrollbacks >=0 and a.isrollbacks<0 and b.isrollbacks<0 then b.isrollbacks-a.isrollbacks when b.isrollbacks-a.isrollbacks>=0 and a.isrollbacks<0 and b.isrollbacks>=0 then b.isrollbacks else 0 end,case when b.longtxs-a.longtxs >=0 and a.longtxs>=0 and b.longtxs>=0 then b.longtxs-a.longtxs when b.longtxs-a.longtxs >=0 and a.longtxs<0 and b.longtxs<0 then b.longtxs-a.longtxs when b.longtxs-a.longtxs>=0 and a.longtxs<0 and b.longtxs>=0 then b.longtxs else 0 end,case when b.bufreads-a.bufreads >=0 and a.bufreads>=0 and b.bufreads>=0 then b.bufreads-a.bufreads when b.bufreads-a.bufreads >=0 and a.bufreads<0 and b.bufreads<0 then b.bufreads-a.bufreads when b.bufreads-a.bufreads>=0 and a.bufreads<0 and b.bufreads>=0 then b.bufreads else 0 end,case when b.bufwrites-a.bufwrites >=0 and a.bufwrites>=0 and b.bufwrites>=0 then b.bufwrites-a.bufwrites when b.bufwrites-a.bufwrites >=0 and a.bufwrites<0 and b.bufwrites<0 then b.bufwrites-a.bufwrites when b.bufwrites-a.bufwrites>=0 and a.bufwrites<0 and b.bufwrites>=0 then b.bufwrites else 0 end,case when b.seqscans-a.seqscans >=0 and a.seqscans>=0 and b.seqscans>=0 then b.seqscans-a.seqscans when b.seqscans-a.seqscans >=0 and a.seqscans<0 and b.seqscans<0 then b.seqscans-a.seqscans when b.seqscans-a.seqscans>=0 and a.seqscans<0 and b.seqscans>=0 then b.seqscans else 0 end,case when b.pagreads-a.pagreads >=0 and a.pagreads>=0 and b.pagreads>=0 then b.pagreads-a.pagreads when b.pagreads-a.pagreads >=0 and a.pagreads<0 and b.pagreads<0 then b.pagreads-a.pagreads when b.pagreads-a.pagreads>=0 and a.pagreads<0 and b.pagreads>=0 then b.pagreads else 0 end,case when b.pagwrites-a.pagwrites >=0 and a.pagwrites>=0 and b.pagwrites>=0 then b.pagwrites-a.pagwrites when b.pagwrites-a.pagwrites >=0 and a.pagwrites<0 and b.pagwrites<0 then b.pagwrites-a.pagwrites when b.pagwrites-a.pagwrites>=0 and a.pagwrites<0 and b.pagwrites>=0 then b.pagwrites else 0 end,case when b.total_sorts-a.total_sorts >=0 and a.total_sorts>=0 and b.total_sorts>=0 then b.total_sorts-a.total_sorts when b.total_sorts-a.total_sorts >=0 and a.total_sorts<0 and b.total_sorts<0 then b.total_sorts-a.total_sorts when b.total_sorts-a.total_sorts>=0 and a.total_sorts<0 and b.total_sorts>=0 then b.total_sorts else 0 end,case when b.dsksorts-a.dsksorts >=0 and a.dsksorts>=0 and b.dsksorts>=0 then b.dsksorts-a.dsksorts when b.dsksorts-a.dsksorts >=0 and a.dsksorts<0 and b.dsksorts<0 then b.dsksorts-a.dsksorts when b.dsksorts-a.dsksorts>=0 and a.dsksorts<0 and b.dsksorts>=0 then b.dsksorts else 0 end,case when b.max_sortdiskspace-a.max_sortdiskspace >=0 and a.max_sortdiskspace>=0 and b.max_sortdiskspace>=0 then b.max_sortdiskspace-a.max_sortdiskspace when b.max_sortdiskspace-a.max_sortdiskspace >=0 and a.max_sortdiskspace<0 and b.max_sortdiskspace<0 then b.max_sortdiskspace-a.max_sortdiskspace when b.max_sortdiskspace-a.max_sortdiskspace>=0 and a.max_sortdiskspace<0 and b.max_sortdiskspace>=0 then b.max_sortdiskspace else 0 end,case when b.logspused-a.logspused >=0 and a.logspused>=0 and b.logspused>=0 then b.logspused-a.logspused when b.logspused-a.logspused >=0 and a.logspused<0 and b.logspused<0 then b.logspused-a.logspused when b.logspused-a.logspused>=0 and a.logspused<0 and b.logspused>=0 then b.logspused else 0 end,case when b.maxlogsp-a.maxlogsp >=0 and a.maxlogsp>=0 and b.maxlogsp>=0 then b.maxlogsp-a.maxlogsp when b.maxlogsp-a.maxlogsp >=0 and a.maxlogsp<0 and b.maxlogsp<0 then b.maxlogsp-a.maxlogsp when b.maxlogsp-a.maxlogsp>=0 and a.maxlogsp<0 and b.maxlogsp>=0 then b.maxlogsp else 0 end from sqlite3_syssesprof a,sqlite3_syssesprof b where a.sid=b.sid and a.utctime<b.utctime;"
	
	mv ${workdir}/fx.temp.db  ${DIR}/fx.${dSt}.db
}

#remainder片数据量核查
fraginit()
{
		dbaccess sysmaster<<EOF 1>>$log 2>&1
		unload to ${dodir}/databases.unl
		select distinct(dbsname)
		from systabnames
		where tabname="fragtabinfo" or tabname="tlm_table"
EOF
	if [ X$? != X0 ]
	then
		log4s error "fraginit()导出所有包含分片管理表的库异常"
	else
		databasenum=`wc -l ${dodir}/databases.unl|awk '{print $1}'`
		if [ X$? != X0 ]
		then
			while read hang
			do
				databasename=`echo $hang|awk -F'|' '{print $1}'`
				log4s info "$databasename 存在分片表，开始检查分片相关信息"
				getrmd $databasename
				notintable $databasename
				getmaxfrag $databasename
			done < ${dodir}/databases.unl
		else
			log4s info "不存在分片表"
		fi
	fi
}
getrmd()
{
	#$1是库名
	#先导出指定库的所有分片
	if [ ! -d $dodir/frag ]
	then
		mkdir $dodir/frag
	fi
	unload1unl="$dodir/frag/$1.fragment.unl.$dS"
	unload2unl="$dodir/frag/$1.fragment.unl.temp.$dS"
	alarmunl="${unload1unl}.$dS"
	echo "unload to $unload1unl select c.tabname,a.partn,b.nrows,a.exprtext[1,9] from sysfragments a,sysmaster:sysptnhdr b,systables c where a.partn=b.partnum and a.tabid=c.tabid" | dbaccess $1 1>/dev/null 2>&1
	if [ $? != 0 ]
	then
		sendalarm "数据库 $1 中，导出sysfragments表数据失败"  $frag_alarmcode
	fi
	grep -a remainder $unload1unl > $unload2unl
	if [ ! -f ${alarmunl} ]
	then
		touch ${alarmunl}
	fi
	awk -v b="$remaindernum" 'BEGIN{FS="|";OFS="|";a=0} {if($3>b && $4=="remainder"){$1=$1;print $0}}' $unload2unl > ${alarmunl}
	alarmunlnum=`wc -l ${alarmunl}|awk '{print $1}'`
	if [ $alarmunlnum != 0 ]
	then
		while read hang
		do
			tabname=`echo "$hang"|awk -F'|' '{print $1}'`
			partnum=`echo "$hang"|awk -F'|' '{print $2}'`
			rows=`echo "$hang"|awk -F'|' '{print $3}'`
			sendalarm "数据库 $1 中，表 ${tabname} 的remainder存在 ${rows} 行数据，超过阀值 ${remaindernum} ，该remainder分片的partnum值为 ${partnum} " $frag_alarmcode
		done < ${alarmunl}
	else
		log4s info "数据库 $1 中，表 ${tabname} 的rmd分区中的数据量正常"
	fi

}
#判断在tlm_table存在但是fragtabinfo不存在的表或者相反
notintable()
{
	#$1是库名
	if [ ! -d $dodir/frag ]
	then
		mkdir $dodir/frag
	fi
	notin1unl="$dodir/frag/notin1.unl.$dS"
	echo "unload to ${notin1unl} select distinct(table_name) from tlm_table where table_name not in(select tabname from fragtabinfo)"|dbaccess $1 1>/dev/null 2>&1;
	if [ $? != 0 ]
	then
		sendalarm "数据库 $1 中，判断表存在于tlm_table但是不存在于fragtabinfo时，从数据库导出数据失败" $frag_alarmcode
	fi
	notin1num=`wc -l $notin1unl|awk '{print $1}'`
	if [ $notin1num != 0 ]
	then
		while read hang
		do
			tabname=`echo $hang|awk -F'|' '{print $1}'`
			sendalarm "数据库 $1 中，表 $tabname 存在于tlm_table，但是不存在于fragtabinfo表。" $frag_alarmcode
		done < $notin1unl
	else
		log4s info "数据库 $1 中，tlm_table表中记录的表都存在于fragtabinfo中，正常"
	fi
	notin2unl="$dodir/frag/notin2.unl.$dS"
	echo "unload to ${notin2unl} select distinct(tabname) from fragtabinfo where tabname not in(select table_name from tlm_table)"|dbaccess $1 1>/dev/null 2>&1;
	if [ $? != 0 ]
	then
		sendalarm "数据库 $1 中，判断表存在于fragtabinfo但是不存在于tlm_table时，从数据库导出数据失败" $frag_alarmcode
	fi
	notin2num=`wc -l $notin2unl|awk '{print $1}'`
	if [ $notin2num != 0 ]
	then
		while read hang
		do
			tabname=`echo $hang|awk -F'|' '{print $1}'`
			sendalarm "数据库 $1 中，表 $tabname 存在于fragtabinfo，但是不存在于表tlm_table。" $frag_alarmcode
		done < $notin2unl
	else
		log4s info "数据库 $1 中，表fragtabinfo中记录的表都存在于tlm_table中，正常"
	fi

}

#判断分片最新日期（当前只能从fragtabinfo获取)
getmaxfrag()
{
	if [ ! -d $dodir/frag ]
	then
		mkdir $dodir/frag
	fi
	allfragtabinfounl="$dodir/frag/allfragtabinfo.unl.$dS"
	echo "unload to $allfragtabinfounl select tabname,max(endtime[1,8]) from fragtabinfo group by tabname"|dbaccess $1 1>/dev/null 2>&1;
	if [ $? != 0 ]
	then
		sendalarm "数据库 $1 中，判断分片最后日期时，从数据库导出数据失败" $frag_alarmcode
	fi
	allfragtabinfounlnum=`wc -l $allfragtabinfounl|awk '{print $1}'`
	if [ $allfragtabinfounlnum != 0 ]
	then
		while read hang
		do
			tabname=`echo $hang|awk -F'|' '{print $1}'`
			tablastday=`echo $hang|awk -F'|' '{print $2}'`
			if [ $okday -gt $tablastday ]
			then
				sendalarm "数据库 $1 中，表 $tabname 分片的最后一片的最后一天时间为 $tablastday ,小于预设的 $fragdaynum 天的阀值" $frag_alarmcode
			else
				log4s info "数据库 $1 中，表 $tabname 分片时间正常"
			fi
		done < $allfragtabinfounl
	else
		log4s info "数据库 $1 中，所有表在fragtabinfo中的最新日期都包括3天后的日期，可以正常使用"
	fi

}
ckptcheck()
{
	tempckptnum=0
	i=0
	dStmp=`date +"%Y%m%d%H%M%S"`
	if [ ! -d $dodir/checkpoint ]
	then
		mkdir $dodir/checkpoint
	fi
	ckptunl="$dodir/checkpoint/ckpt.unl.temp.$dStmp"
	while true
	do
		let i=i+1
		echo "unload to $ckptunl select sh_cpflag from sysshmvals"|dbaccess sysmaster 1>/dev/null 2>&1;
#		if [ $tflag = 1 ]
#		then
#			if [ $i = 1 ]
#			then
#				echo 1 > $ckptunl
#			elif [ $i = 2 ]
#			then
#				echo 0 >  $ckptunl
#			fi
#		elif [ $tflag = 2 ]
#		then
#			if [ $i = 1 ]
#			then
#				echo 0 > $ckptunl
#			elif [ $i = 2 ]
#			then
#				echo 1 >  $ckptunl
#			fi
#		elif [ $tflag = 3 ]
#		then
#			if [ $i = 1 ]
#			then
#				echo 1 > $ckptunl
#			elif [ $i = 2 ]
#			then
#				echo 1 >  $ckptunl
#			fi
#		fi
		if [ $? != 0 ]
		then
			sendalarm "判断ckpt状态时，从数据库导出数据失败，请尽快查看" $ckpt_alarmcode
			ckptstatus=1
		else
			ckptstatus=`tail  $ckptunl|awk -F'|' '{print $1}'`
		fi
		
		if [ $testflag = 0 ]
		then
			rm -rf $ckptunl
		fi
		if [ $ckptstatus = 1 ]
		then
			let tempckptnum=tempckptnum+1
			log4s warn "第 $i 次检查，当前为ckpt状态，等待 $ckptnumjiange 秒后继续检查"
			if [ $tempckptnum = $ckptnum ]
			then
				sendalarm "ckpt状态已经连续 $ckptnum 次，每次间隔 $ckptnumjiange 秒处于ckpt状态，请检查数据库" $frag_alarmcode
				break;
			fi
			sleep $ckptnumjiange;
		else
			log4s info "ckpt状态正常"
			break;
		fi
		if [ $i -eq $ckptnum ]
		then
			break;
		fi
	done
}

seqbasic()
{
	log4s info "开始执行顺扫检查"
	seqbasicworkdir=$dodir/seq
	if [ ! -d $seqbasicworkdir ]
	then
		mkdir $seqbasicworkdir
	fi
	dSt=`date +"%Y%m%d%H%M%S"`
	dbaccess sysmaster <<EOF 1>>$log 2>&1
	unload to $seqbasicworkdir/table.$dSt.temp
	select "$dSt",a.lockid,a.partnum,b.tabname,c.tabname,b.dbsname,a.flags,a.nrows,d.seqscans
	from sysmaster:sysptnhdr a, sysmaster:systabnames b,sysmaster:systabnames c
	--可以添加sysptprof表等
	,sysmaster:sysptprof d
	where a.partnum=b.partnum
	and a.lockid=c.partnum
	--from中出现两次systabnames，是为了分别提供partnum和lockid的tabname，确定索引和表的关系。
	and a.flags not in ('2310','2054','3334','3078','2081')
	--指定数据库
	--and b.dbsname='min'
	--业务主控：
	and a.partnum=d.partnum and d.seqscans>0
	group by a.lockid,a.partnum,b.tabname,c.tabname,b.dbsname,a.nrows,d.seqscans,a.flags
	order by a.partnum
EOF
	sed 's/.$//' $seqbasicworkdir/table.$dSt.temp > ${seqbasicworkdir}/table.$dSt.temp.a
	rm -rf $seqbasicworkdir/table.$dSt.temp
	mv ${seqbasicworkdir}/table.$dSt.temp.a ${seqbasicworkdir}/table.new


	if [ ! -f ${seqbasicworkdir}/table.old ]
	then
		mv ${seqbasicworkdir}/table.new ${seqbasicworkdir}/table.old
	else
		gosqlite3 "create table seqfx(timenow text,lockid  integer,partnum integer,tabname1 text,tabname2 text,dbsname text,flags integer,nrows integer,seqscans integer);"
		gosqlite3 ".import ${seqbasicworkdir}/table.old seqfx"
		gosqlite3 ".import ${seqbasicworkdir}/table.new seqfx"
		gosqlite3 "create index idx_seqfx on seqfx(partnum);"
		gosqlite3 "select b.timenow,b.lockid,b.partnum,b.tabname1,b.tabname2,b.dbsname,b.flags,b.nrows,b.seqscans-a.seqscans from seqfx a,seqfx b where a.partnum=b.partnum and a.timenow<b.timenow;">${seqbasicworkdir}/table.${dSt}.temp
		mv ${workdir}/fx.temp.db ${seqbasicworkdir}/seq.${dSt}.table_info.db

		mv ${seqbasicworkdir}/table.new ${seqbasicworkdir}/table.old
		cp ${seqbasicworkdir}/table.old ${seqbasicworkdir}/table.${dSt}.old
		cat ${seqbasicworkdir}/table.${dSt}.temp|sort -r -t "|" -k 9 > ${seqbasicworkdir}/table.${dSt}.unl
		gohtml ${dSt}
	fi
}
seqonehour()
{
	log4s info "开始执行顺扫一小时检查检查"
	seqbasicworkdir=$dodir/seq
	if [ ! -d $seqbasicworkdir ]
	then
		mkdir $seqbasicworkdir
	fi
	dSt=`date +"%Y%m%d%H%M%S"`
	dbaccess sysmaster <<EOF 1>>$log 2>&1
	unload to $seqbasicworkdir/table.onehour.$dSt.temp
	select "$dSt",a.lockid,a.partnum,b.tabname,c.tabname,b.dbsname,a.flags,a.nrows,d.seqscans
	from sysmaster:sysptnhdr a, sysmaster:systabnames b,sysmaster:systabnames c
	--可以添加sysptprof表等
	,sysmaster:sysptprof d
	where a.partnum=b.partnum
	and a.lockid=c.partnum
	--from中出现两次systabnames，是为了分别提供partnum和lockid的tabname，确定索引和表的关系。
	and a.flags not in ('2310','2054','3334','3078','2081')
	--指定数据库
	--and b.dbsname='min'
	--业务主控：
	and a.partnum=d.partnum and d.seqscans>0
	group by a.lockid,a.partnum,b.tabname,c.tabname,b.dbsname,a.nrows,d.seqscans,a.flags
	order by a.partnum
EOF
	sed 's/.$//' $seqbasicworkdir/table.onehour.$dSt.temp > ${seqbasicworkdir}/table.onehour.$dSt.temp.a
	rm -rf $seqbasicworkdir/table.onehour.$dSt.temp
	mv ${seqbasicworkdir}/table.onehour.$dSt.temp.a ${seqbasicworkdir}/table.onehour.new


	if [ ! -f ${seqbasicworkdir}/table.onehour.old ]
	then
		mv ${seqbasicworkdir}/table.onehour.new ${seqbasicworkdir}/table.onehour.old
	else
		gosqlite3 "create table seqfx(timenow text,lockid  integer,partnum integer,tabname1 text,tabname2 text,dbsname text,flags integer,nrows integer,seqscans integer);"
		gosqlite3 ".import ${seqbasicworkdir}/table.onehour.old seqfx"
		gosqlite3 ".import ${seqbasicworkdir}/table.onehour.new seqfx"
		gosqlite3 "create index idx_seqfx on seqfx(partnum);"
		gosqlite3 "select b.timenow,b.lockid,b.partnum,b.tabname1,b.tabname2,b.dbsname,b.flags,b.nrows,b.seqscans-a.seqscans from seqfx a,seqfx b where a.partnum=b.partnum and a.timenow<b.timenow;">${seqbasicworkdir}/table.onehour.${dSt}.temp
		mv ${workdir}/fx.temp.db ${seqbasicworkdir}/seq.onehour.${dSt}.table_info.db

		mv ${seqbasicworkdir}/table.onehour.new ${seqbasicworkdir}/table.onehour.old
		cp ${seqbasicworkdir}/table.onehour.old ${seqbasicworkdir}/table.onehour.${dSt}.old
		cat ${seqbasicworkdir}/table.onehour.${dSt}.temp|sort -r -t "|" -k 9 > ${seqbasicworkdir}/table.onehour.${dSt}.unl
		gohtmlonehour ${dSt}
	fi
}
gohtml()
{
	dSt=$1
	tableunl=${seqbasicworkdir}/table.$1.unl
	if [ ! -f $tableunl ]
	then
		log4s error "不存在$tableunl，无法生成顺扫报告"
		return 1;
	fi
	if [ ! -f $dodir/seqscan.log ]
	then
		touch $dodir/seqscan.log
		chmod 777 $dodir/seqscan.log
	fi
	if [ ! -f $seqbaogao ]
	then
		touch $seqbaogao
		chmod 777 $seqbaogao
	fi
	firstxhtmlnu=`wc -l $seqbaogao|awk '{print $1}'`
	if [ X$firstxhtmlnu = X0 ]
	then
		log4s info "报告无记录，生成报告头部"
		xhtml "<html><head><title>顺序扫描记录</title></head><body>" 
		xhtml "<table border="1">"
		xhtml "<tr>"
		xhtml "<th>时间</th><th>表名</th><th>partnum</th><th>行数</th><th>顺序扫描次数</th>"
		xhtml "</tr>"
	else
		log4s info "报告已经存在记录，取消报告尾部"
		mv $seqbaogao ${seqbaogao}.${dSt}
		sed "/<\/table>/d" ${seqbaogao}.${dSt}|sed "/<\/body>/d" > $seqbaogao
		rm -rf ${seqbaogao}.${dSt}
	fi
	while read hang
	do
		tabname=`echo $hang|awk -F'|' '{print $5}'`
		partnum=`echo $hang|awk -F'|' '{print $3}'`
		nrows=`echo $hang|awk -F'|' '{print $8}'`
		seq=`echo $hang|awk -F'|' '{print $9}'|awk -F'.' '{print $1}'`
		if [ $seq -ge $seq_alarmnum1 ]
		then
			if [ $nrows -ge $seq_alarmrow1 ]
			then
				xhtml "<tr>"
				xhtml "<th>$dSt</th>"
				xhtml "<th>$tabname</th>"
				xhtml "<th>$partnum</th>"
				xhtml "<th>$nrows</th>"
				xhtml "<th>$seq</th>"
				xhtml "</tr>"
				echo "$dSt 表名：$tabname ,partnum：$partnum ,行数：$nrows ,alarm1 table seq is too large" >> $dodir/seqscan.log
				sendalarm "$dSt 表名：$tabname ,partnum：$partnum ,行数：$nrows ,alarm1 table seq is too large" $seq_alarmcode
			fi
		else
			break;
		fi
	done < ${seqbasicworkdir}/table.${dSt}.unl
	xhtml "</table>"
	xhtml "</body></html>"
}
gohtmlonehour()
{
	dSt=$1
	tableunl=${seqbasicworkdir}/table.onehour.$1.unl
	if [ ! -f $tableunl ]
	then
		log4s error "不存在$tableunl，无法生成顺扫报告"
		return 1;
	fi
	if [ ! -f $dodir/seqscan.log ]
	then
		touch $dodir/seqscan.log
		chmod 777 $dodir/seqscan.log
	fi
	if [ ! -f $seqbaogao ]
	then
		touch $seqbaogao
		chmod 777 $seqbaogao
	fi
	firstxhtmlnu=`wc -l $seqbaogao|awk '{print $1}'`
	if [ X$firstxhtmlnu = X0 ]
	then
		log4s info "报告无记录，生成报告头部"
		xhtml "<html><head><title>顺序扫描记录</title></head><body>" 
		xhtml "<table border="1">"
		xhtml "<tr>"
		xhtml "<th>时间</th><th>表名</th><th>partnum</th><th>行数</th><th>顺序扫描次数</th>"
		xhtml "</tr>"
	else
		log4s info "报告已经存在记录，追加内容"
		mv $seqbaogao ${seqbaogao}.${dSt}
		sed "/<\/table>/d" ${seqbaogao}.${dSt}|sed "/<\/body>/d" > $seqbaogao
		rm -rf ${seqbaogao}.${dSt}
	fi
	while read hang
	do
		tabname=`echo $hang|awk -F'|' '{print $5}'`
		partnum=`echo $hang|awk -F'|' '{print $3}'`
		nrows=`echo $hang|awk -F'|' '{print $8}'`
		seq=`echo $hang|awk -F'|' '{print $9}'|awk -F'.' '{print $1}'`
		if [ $seq -ge $seq_alarmnum2 ]
		then
			if [ $nrows -ge $seq_alarmrow2 ]
			then
				xhtml "<tr>"
				xhtml "<th>$dSt</th>"
				xhtml "<th>$tabname</th>"
				xhtml "<th>$partnum</th>"
				xhtml "<th>$nrows</th>"
				xhtml "<th>$seq</th>"
				xhtml "</tr>"
				echo "$dSt 表名：$tabname ,partnum：$partnum ,行数：$nrows ,alarm1 table seq is too large" >> $dodir/seqscan.log
				sendalarm "$dSt 表名：$tabname ,partnum：$partnum ,行数：$nrows ,alarm1 table seq is too large" $seq_alarmcode
			fi
		else
			break;
		fi
	done < ${seqbasicworkdir}/table.onehour.${dSt}.unl
	xhtml "</table>"
	xhtml "</body></html>"
}

checknptotal()
{
	dSt=`date +"%Y%m%d%H%M%S"`
	npdir=$dodir/npused
	if [ ! -d $npdir ]
	then
		mkdir $npdir
	fi
	dbaccess sysmaster <<EOF 1>>$log 2>&1
	unload to $npdir/npused.$dSt.temp
	select b.partnum,b.dbsname,b.tabname,a.nptotal 
	from sysptnhdr a,systabnames b
	where a.partnum=b.partnum
	and a.nptotal>$nptotal_threshold
	order by a.nptotal
EOF
	npalarnum=`wc -l $npdir/npused.$dSt.temp|awk '{print $1}'`
	if [ $npalarnum != 0 ]
	then
		log4s error "存在page数大于 $nptotal_threshold 的表，具体请观察 $alarmlog"
		while read hang
		do
			nppartnum=`echo "$hang" |awk -F'|' '{print $1}'`
			npdbsname=`echo "$hang" |awk -F'|' '{print $2}'`
			nptabname=`echo "$hang" |awk -F'|' '{print $3}'`
			nptotal=`echo "$hang" |awk -F'|' '{print $4}'`
			sendalarm "表名：$nptabname ，所在库：$npdbsname ，partnum：$nppartnum ，当前page数为：$nptotal" $nptotal_alarmcode
		done < $npdir/npused.$dSt.temp
	fi
}
transformDay2onlinelog()
{
	dweekt=$(date -d "$1" +%w)
	dmontht=$(date -d "$1" +%m)
	ddayt=$(date -d "$1" +%d)
	dyear=$(date -d "$1" +%y)
	case $dweekt in
		"0")
			dweek="Sun"
			;;
		"1")
			dweek="Mon"
			;;
		"2")
			dweek="Tue"
			;;
		"3")
			dweek="Wed"
			;;
		"4")
			dweek="Thu"
			;;
		"5")
			dweek="Fri"
			;;
		"6")
			dweek="Sat"
			;;
		esac
		case $dmontht in
		"01")
			dmonth="Jan"
			;;
		"02")
			dmonth="Feb"
			;;
		"03")
			dmonth="Mar"
			;;
		"04")
			dmonth="Apr"
			;;
		"05")
			dmonth="May"
			;;
		"06")
			dmonth="Jun"
			;;
		"07")
			dmonth="Jul"
			;;
		"08")
			dmonth="Aug"
			;;
		"09")
			dmonth="Sep"
			;;
		"10")
			dmonth="Oct"
			;;
		"11")
			dmonth="Nov"
			;;
		"12")
			dmonth="Dec"
			;;
		esac
		ddayt1=${ddayt:0:1}
		ddayt2=${ddayt:0:2}
		if [ $ddayt1 = 0 ]
		then
			dday=" ${ddayt2:1:2}"
		else
			dday="$ddayt"
		fi
		echo "$dweek $dmonth $dday"
	
}
checkBackSuccess()
{
	dSt=`date +"%Y%m%d%H%M%S"`
	IDSLog=`grep ^MSGPATH $INFORMIXDIR/etc/$ONCONFIG|awk '{print $2}'`
	templog=$dodir/online.log.$dSt.temp
	templog1=$dodir/online.log.$dSt.temp1
	if [ $? = 0 ]
	then
		log4s info "获取online.log日志目录成功"
	else
		log4s error "获取online.log日志目录异常"
	fi
	#获取昨天日期并转换为onlin.log中格式
	onlogd1dayago="$(transformDay2onlinelog $d1dayago)"
	#截取日志最后2w行
	tail -$onlinelogtempnum $IDSLog > $templog
	#获取昨天日期最后一行的行号
	lastonlogd1dayagonum=`awk -v onlogd1dayago="$onlogd1dayago" '/'"$onlogd1dayago"'/{print NR}' $templog|tail -1`
	#容错，如果没有匹配到，就整个文件都是
	if [ X$lastonlogd1dayagonum = X ]
	then
		lastonlogd1dayagonum=0
	fi
	let in1daylog=onlinelogtempnum-lastonlogd1dayagonum
	tail -$in1daylog $templog > $templog1
	#获取成功昨天到今天的日志内容
	archiveoknum=`grep "Archive on" $templog1|grep Completed|wc -l|awk '{print $1}'`
	if [ $archiveoknum -ge 1 ]
	then
		log4s info "零备成功"
	else
		log4s error "没有检测到零备成功日志，请确认是否正常"
		sendalarm "没有检测到零备成功日志，请确认是否正常" $onlinelogbak_alarmcode
	fi
	
}
checkidxlevel()
{
	#检查索引必须在Table_Info执行后才可以执行
	sysindexinfo=${dodir}/sysindex.now
	if [ ! -f $sysindexinfo ]
	then
		log4s error "索引信息不存在，请重新核查。"
	else
		while read hang
		do
			idxlevels=`echo "$hang"|awk -F'|' '{print $27}'`
			if [ X$idxlevels != X ]
			then
				if [ $idxlevels -gt $idxlevel_threshold ]
				then
					idxname=`echo "$hang"|awk -F'|' '{print $6}'`
					tabname=`echo "$hang"|awk -F'|' '{print $31}'`
					databasename=`echo "$hang"|awk -F'|' '{print $5}'`
					sendalarm "库${databasename} : 表${tabname} : 索引${idxname} 层数大于 ${idxlevel_threshold} " $idxlevel_alarmcode
				fi
			fi
		done < $sysindexinfo
	fi
}
checklock()
{
	#为了性能，先判断总量，如果总量超出了再判断单个
	lockeachtempunl=${dodir}/syslocksach.$dS.unl
	echo "unload to $lockeachtempunl select owner,count(*) from syslocks group by owner having count(*)>$locks_threshold2"|dbaccess sysmaster
	if [ $? = 0 ]
	then
		eachlocknum=`wc -l $lockeachtempunl | awk '{print $1}'`
		if [ X$eachlocknum != X0 ]
		then
			while read hang
			do
				owner=`echo $hang|awk -F'|' '{print $1}'`
				ownerlockcount=`echo $hang|awk -F'|' '{print $2}'|awk -F'.' '{print $1}'`
				sendalarm "owner:$owner 同时存在 $ownerlockcount 个锁" $locks_alarmcode
			done < $lockeachtempunl
		else
			log4s info "锁检查正常"
			rm -rf $lockeachtempunl
		fi
	else
		sendalarm "导出每个owner锁时异常" $locks_alarmcode
	fi
	
}
GetPerformance()
{
	log4s info "Enter main loop"
	mkdir $workdir/vm 1>/dev/null 2>&1
	mkdir $workdir/net 1>/dev/null 2>&1
	mkdir $workdir/disk 1>/dev/null 2>&1
	#在主循环中，执行统计和处理文件都在后台执行，保证统计的完整
	while true
	do
		log4s info "In the main loop"

		#根据当前时间，获取这次循环要运行的时间
		runSec=`getResidueSec`
		let runSec=runSec-1
		dH=`date +"%Y%m%d%H"`
		dS=`date +"%Y%m%d%H%M%S"`

		nohup vmstat 1     $runSec|awk -v dbid="$dbid" -v time="$time" -v utctime="$timenowUTC" -v OFS="|" '{$1=$1;print 0,dbid,strftime("%Y%m%d%H%M%S"),strftime("%s"),$0}' > $workdir/vm/p_vm.$dS 2>&1 &
		nohup sar -n DEV 1 $runSec|awk -v dbid="$dbid" -v time="$time" -v utctime="$timenowUTC" -v OFS="|" '{$1=$1;print 0,dbid,strftime("%Y%m%d%H%M%S"),strftime("%s"),$0}' > $workdir/net/p_network.$dS 2>&1 &
		nohup sar -p -d 1  $runSec|awk -v dbid="$dbid" -v time="$time" -v utctime="$timenowUTC" -v OFS="|" '{$1=$1;print 0,dbid,strftime("%Y%m%d%H%M%S"),strftime("%s"),$0}' > $workdir/disk/p_disk.$dS 2>&1 &
		sleep $runSec;

		grep -v "procs"       $workdir/vm/p_vm.$dS        |grep -v "swpd"                  >> $workdir/vm/p_vm.log.$dH
		grep -v "IFACE|rxpck" $workdir/net/p_network.$dS  |grep -v "Linux"|grep -v "|$"    >> $workdir/net/p_network.log.$dH
		grep -v "DEV"         $workdir/disk/p_disk.$dS    |grep -v "Linux"|grep -v "|$"    >> $workdir/disk/p_disk.log.$dH
		
		rm -rf $workdir/vm/p_vm.$dS;
		rm -rf $workdir/net/p_network.$dS;
		rm -rf $workdir/disk/p_disk.$dS;
		
		#删除指定天数之前的记录文件
		#获取指定天数之前的日期
		log4s info "开始删除过期文件"
		rmday=`DOY $reservation_pmon|awk -F'-' '{print $1$2$3}'`
		log4s info "GetPerformance 过期日期为 $rmday"
		rm -rf $workdir/vm/p_vm.log.${rmday}*;
		rm -rf $workdir/net/p_network.log.${rmday}*;
		rm -rf $workdir/disk/p_disk.log.${rmday}*;
	done
	
}

#top单独处理，如果有要调用top的功能时，使用自身调用。方式是参数top且为一个时，执行top模式；如果参数列表中有top或者为all的时候，用前一个方式调用top。
GetTop()
{
	log4s info "Enter top main loop"
	mkdir $workdir/top 1>/dev/null 2>&1
	while true
	do
		dH=`date +"%Y%m%d%H"`
		dS=`date +"%Y%m%d%H%M%S"`
		if [ X$os = XLINUX ]
		then
			nohup top -b -n 1   |awk -v dbid="$dbid" -v time="$time" -v utctime="$timenowUTC" -v OFS="|" '{$1=$1;print 0,dbid,strftime("%Y%m%d%H%M%S"),strftime("%s"),$0}'|head -30>$workdir/top/p_top.$dS &
			if [ X$wai = Xroot ]
			then
				nohup iotop -b -n 1 |awk -v dbid="$dbid" -v time="$time" -v utctime="$timenowUTC" -v OFS="|" '{$1=$1;print 0,dbid,dbid,strftime("%Y%m%d%H%M%S"),strftime("%s"),$0}'|head -30>$workdir/top/p_iotop.$dS &
			fi
			sleep 1;
			head -22 $workdir/top/p_top.$dS   | sed "1,7d" >> $workdir/top/p_top.log.$dH
			rm -rf $workdir/top/p_top.$dS;
			if [ X$wai = Xroot ]
			then
				head -22 $workdir/top/p_iotop.$dS | sed "1,2d" >> $workdir/top/p_iotop.log.$dH
				rm -rf $workdir/top/p_iotop.$dS;
			fi

		else
			log4s error "OS is not support  $os"
		fi
		
		#删除指定天数之前的记录文件
		#获取指定天数之前的日期
		rmday=`DOY $reservation_pmon|awk -F'-' '{print $1$2$3}'`
		rm -rf $workdir/top/p_top.log.${rmday}*;
		if [ X$wai = Xroot ]
		then
			rm -rf $workdir/top/p_iotop.log.${rmday}*;
		fi
	done
}
analysis()
{
	lenstarttime=`echo "$1"|wc -L`
	lenendtime=`echo "$2"|wc -L`
	if [ $lenstarttime = 19 ]
	then
		#格式为2018-09-30 16:04:02，直接转换为utc
		starttimet="$1"
		starttime=`date -d "$starttimet" +"%s"`
	elif [ $lenstarttime = 14 ]
	then
		#格式为20180930160402，需要转换为上面的格式再转换为utc
		starttimet="${1:0:4}-${1:4:2}-${1:6:2} ${1:8:2}:${1:10:2}:${1:12:2}"
		starttime=`date -d "$starttimet" +"%s"`
	elif [ $lenstarttime = 10 ]
	then
		#格式为utc，不需要转换
		starttime="$1"
	else
		#异常格式，不处理
		log4s error "起始时间参数格式不正确，不处理"
		exit 1;
	fi
	if [ $lenendtime = 19 ]
	then
		#格式为2018-09-30 16:04:02，直接转换为utc
		endtimet="$2"
		endtime=`date -d "$starttimet" +"%s"`
	elif [ $lenendtime = 14 ]
	then
		#格式为20180930160402，需要转换为上面的格式再转换为utc
		endtimet="${2:0:4}-${2:4:2}-${2:6:2} ${2:8:2}:${2:10:2}:${2:12:2}"
		endtime=`date -d "$starttimet" +"%s"`
	elif [ $lenendtime = 10 ]
	then
		#格式为utc，不需要转换
		endtime="$2"
	else
		#异常格式，不处理
		log4s error "结束时间参数格式不正确，不处理"
		exit 1;
	fi
	log4s info "起始时间为： $starttime  结束时间为： $endtime   开始获取范围内日志"
	log4s info "合并记录日志"
	cat $workdir/vm/p_vm.log.??????????           > $workdir/all_vm.log
	cat $workdir/net/p_network.log.??????????  > $workdir/all_net.log
	cat $workdir/disk/p_disk.log.??????????        > $workdir/all_disk.log
	log4s info "开始处理vm的内容"
	awk -v starttime="$starttime" -v endtime="$endtime" -F'|' '{if($3>starttime && $3<endtime){print $0}}'  $workdir/all_vm.log   > $workdir/result_vm.log
	log4s info "开始处理net的内容"
	awk -v starttime="$starttime" -v endtime="$endtime" -F'|' '{if($3>starttime && $3<endtime){print $0}}'  $workdir/all_net.log   > $workdir/result_net.log
	log4s info "开始处理disk的内容"
	awk -v starttime="$starttime" -v endtime="$endtime" -F'|' '{if($3>starttime && $3<endtime){print $0}}'  $workdir/all_disk.log  > $workdir/result_disk.log
	rm -rf  $workdir/all_vm.log
	rm -rf  $workdir/all_net.log
	rm -rf  $workdir/all_disk.log
	sort  -t"|" -k 4 -n $workdir/result_vm.log    > $workdir/result_vm.log1
	sort  -t"|" -k 4 -n $workdir/result_net.log    > $workdir/result_net.log1
	sort  -t"|" -k 4 -n $workdir/result_disk.log   > $workdir/result_disk.log1
	mv $workdir/result_vm.log1 $workdir/result_vm.log
	mv $workdir/result_net.log1 $workdir/result_net.log
	mv $workdir/result_disk.log1 $workdir/result_disk.log
}
qingli()
{
	rm -rf ${DIR}/sysdri.${dS}.temp
	rm -rf ${DIR}/sysenv.${dS}.temp
	rm -rf ${DIR}/machineinfo.${dS}.temp
	rm -rf ${DIR}/sysshmvals.${dS}.temp
	rm -rf ${DIR}/sysdatabases.${dS}.temp
	rm -rf ${DIR}/sysprofile.${dS}.temp
	rm -rf ${DIR}/syssegments.${dS}.temp
	rm -rf ${DIR}/sysvplst.${dS}.temp
	rm -rf ${DIR}/syschktab.${dS}.temp
	rm -rf ${DIR}/sysdbspaces.${dS}.temp
	rm -rf ${DIR}/syschunks.${dS}.temp
	rm -rf ${DIR}/sysindexes.$dS.temp.*
	rm -rf ${DIR}/systables.$dS.temp.*
	rm -rf ${DIR}/sysptprof.${dS}.temp
	rm -rf ${DIR}/systabinfo.${dS}.temp
	rm -rf ${DIR}/sysfragments.$dS.temp.*
	rm -rf ${DIR}/syssessions.${dS}.temp
	rm -rf ${DIR}/syssesprof.${dS}.temp
	rm -rf ${DIR}/syslogs.${dS}.temp
	rm -rf ${DIR}/syslogfil.${dS}.temp
	rm -rf ${DIR}/sysconfig.${dS}.temp
	rm -rf ${DIR}/syssqlhosts.${dS}.temp
	rm -rf ${DIR}/hb_sqlite3_sysprofile.${dS}.temp
	rm -rf ${DIR}/hb_sqlite3_sysvplst.${dS}.temp
	rm -rf ${DIR}/hb_sqlite3_syschktab.${dS}.temp
	rm -rf ${DIR}/hb_sqlite3_sysptprof.${dS}.temp
	rm -rf ${DIR}/hb_sqlite3_syssessions.${dS}.temp
	rm -rf ${DIR}/hb_sqlite3_syssesprof.${dS}.temp
	rm -rf ${DIR}/fx.*.db
	rm -rf $dodir/table.${dtempbakdate}*.unl
	rm -rf $dodir/seqscan.${dtempbakdate}*.html
	rm -rf $dodir/fx.${dtempbakdate}*.db
	rm -rf ${workdir}/fx.temp.db
	rm -rf ${dodir}/table.${dtempbakdate}*.temp
	rm -rf ${dodir}/${dtempbakdate}??
	rm -rf $allfragtabinfounl
	rm -rf $ckptunl
	rm -rf $unload1unl
	rm -rf $unload2unl
	rm -rf $alarmunl
	rm -rf $notin1unl
	rm -rf $notin2unl
	rm -rf $npdir/npused.${dtempbakdate}*.temp
	rm -rf ${dodir}/online.log.*.temp
	rm -rf ${dodir}/online.log.*.temp1
	rm -rf $seqbasicworkdir/table.*.temp
	rm -rf $seqbasicworkdir/table.${dtempbakdate}*.old
	rm -rf $seqbasicworkdir/table.*.unl
	rm -rf $seqbasicworkdir/fx.*.table_info.db
	rm -rf $seqbasicworkdir/table.onehour.*.temp
	rm -rf $seqbasicworkdir/table.onehour.${dtempbakdate}*.old
	rm -rf $seqbasicworkdir/table.onehour.*.unl
	rm -rf $seqbasicworkdir/fx.onehour.*.table_info.db
	rm -rf ${dodir}/syslocks.${dtempbakdate}*.unl
	rm -rf ${dodir}/syslocksach.${dtempbakdate}*.unl
}

#控制执行频率
frequency()
{
	allinit
	dbversionBig=`onstat -V |awk '{print $6}'|awk -F'.' '{print $1}'`
	if [ ! -f $TAGLOG ]
	then
		touch $TAGLOG
	fi
	DAYTAG=TAGDAY-`date +'%Y-%m-%d'`-TAGEND
	DAYTAGEXIST=`grep "$DAYTAG" $TAGLOG |wc -l|awk '{print $1}'`	
	let dMcount=dMonly/5
	FIVEMINTAG=TAGFIVEMIN-${dH}`printf '%02d' $dMcount`-TAGEND
	FIVEMINTAGEXIST=`grep "$FIVEMINTAG" $TAGLOG |wc -l|awk '{print $1}'`
	ONEHOURTAG=TAGONEHOUR-`date +'%Y-%m-%d-%H'`-TAGEND
	ONEHOURTAGEXIST=`grep "$ONEHOURTAG" $TAGLOG |wc -l|awk '{print $1}'`

	#每天执行一次的
	if [ X$DAYTAGEXIST = X0 ]
	then
		if [ $dHonly = 22 ] && [ $dMonly = 22 ]
		then
			echo $DAYTAG >> $TAGLOG
			log4srotate
			log4s info "脚本$dt第一次执行，执行每天任务"
			Global_Info
			Config_info
			SQLHOSTS
			checkBackSuccess
			checkidxlevel
			find $DIR -name "*.temp" -atime +7 -exec rm -rf {} \;
		else
			log4s info "每天执行一次，当前不是22点22分，不执行"
		fi

	fi
	#每小时一次的任务
	if [ X$ONEHOURTAGEXIST = X0 ]
	then
		if [ $dMonly = 22 ]
		then
			echo $ONEHOURTAG >> $TAGLOG
			log4s info "执行每小时任务"
			ckptcheck
			checknptotal
			fraginit
			
			DB_Profile
			Memory_Info
			Process_Info
			Disk_Info
			Table_Info
			Log_info
			Session_info
			if [ $sqlite3flag = 1 ]
			then
				sqlite3huanbi
			fi
		else
			log4s info "每小时执行一次，当前不是22分，不执行"
		fi

	fi
	#五分钟一次的
	if [ X$FIVEMINTAGEXIST = X0 ]
	then
		echo $FIVEMINTAG >> $TAGLOG
		log4s info "执行5分钟任务"
		checklock
	fi

	log4s info "执行每次任务"
	seqbasic
	
	cron_config $dbid $workdir
	if [ $debugrmflag = 0 ]
	then
		qingli
	fi
}
cron_config()
{
	PROGRAM="$workdir/$jiaobenming $1 $2"
	if [ $XITONG = LINUX ]
	then
	CRONTAB_CMD="* * * * * . ./.bash_profile;sh $PROGRAM >> $workdir/cron.log 2>&1 &"
	fi
	if [ $XITONG = HP-UX ]
	then
	CRONTAB_CMD="* * * * * . ./.profile;sh $PROGRAM >> $workdir/cron.log 2>&1 &"
	fi
	PROGRAMnum=`crontab -l|grep "$PROGRAM"|wc -l|awk '{print $1}'`
	if [ X$PROGRAMnum = X0 ]
	then
		log4s info "定时不存在，将定时加入系统cron"
		crontab -l>$workdir/cron.temp
		echo "$CRONTAB_CMD" >> $workdir/cron.temp
		cat $workdir/cron.temp|crontab
	else
		log4s info "定时存在，不做操作"
	fi
}
update_cron_config()
{
	PROGRAM="$workdir/$jiaobenming $1 $2 $3 $4 $5 $6"
	if [ $XITONG = LINUX ]
	then
	CRONTAB_CMD=". ./.bash_profile;sh $PROGRAM >> $workdir/cron.log 2>&1 &"
	fi

	PROGRAMnum=`crontab -l|grep "$PROGRAM"|wc -l|awk '{print $1}'`
	if [ X$PROGRAMnum = X0 ]
	then
		log4s info "定时不存在，将定时加入系统cron"
		crontab -l>$workdir/cron.temp
		echo "2 2 * * * $CRONTAB_CMD" >> $workdir/cron.temp
		cat $workdir/cron.temp|crontab
		log4s info "请根据需求调整定时时间"
	else
		log4s info "定时存在，不做操作"
	fi
}
update_init()
{
	if [ ! -d $updatedir ]
	then
		log4s info "创建update目录"
		mkdir $updatedir
	fi
	table=$updatedir/tab.unl
	t=0
	
	if [ X$TYPE = Xzhou ]
	then
		tag=TAGWEEK-`date +%Y%V`
		upmain;
	fi
	
	if [ X$TYPE = Xyue ]
	then
		tag=TAGMONTH-`date +%Y%m`
		upmain;
	fi
	
	if [ X$TYPE = Xnian ]
	then
		tag=TAGYEAR-`date +%Y`
		upmain;
	fi
	
	if [ X$TYPE = Xbuxian ]
	then
		tag=TAGwuxian-`date +%Y%m%d%H%M%S`
		upmain;
	fi
}
upmain()
{
	if [ ! -f $updatetaglog ]
	then
		tagexist=0
	else
		tagexist=`grep "$tag" $updatetaglog |wc -l|awk '{print $1}'`
	fi
	if [ ! -f $table ]
	then
		hangshu=0
	else
		hangshu=`wc -l $table|awk '{print $1}'`
	fi
	
	if [ ! -f $table ]
	then
		daochu;
		echo $tag >> $updatetaglog
		update;
	else
		if [ X$tagexist = X0 ]
		then
			if [ X$hangshu = X0 ]
			then
				daochu;
				echo $tag >> $updatetaglog
				update;
			else
				update;
			fi
		else
			if [ X$hangshu = X0 ]
			then
				log4s info "本周期已经统计更新完成，不再重复执行"
			else
				update;
			fi
		fi
	fi
}
daochu()
{
dbaccess $DBNAME <<!
unload to $table delimiter ' '
select a.tabname,b.ti_nrows from ${DBNAME}:systables a,sysmaster:systabinfo b
where a.partnum=b.ti_partnum
and a.tabid >99
and a.tabtype='T'
!
	
	filterindex=0
	while [ $filterindex -lt ${#filter[*]} ]
	do
		grep -v "${filter[$filterindex]} " $table > $table.temp
		let filterindex+=1
		mv $table.temp $table
	done
	log4s info "导出要更新的表成功"
}


update()
{
while read A B
do
	if [ $t -lt $RECORDNUM ]
	then
		t=`expr ${B%.*} + $t`
		dbaccess $DBNAME <<!
		update statistics medium for table $A;
!
		if [ $? = 0 ]
		then 
			log4s info "`date` UPDATE STATISTICS medium for table $A  OK"
			sed "/^$A /d" $table > $table.temp1
			mv $table.temp1 $table
		else 
			log4s info "$A update执行失败"
			exit 1
		fi
	fi
done < $table
}
loadandrm()
{
	#判断是否失败的，失败的一天导入一次
	cd $DIR;
	badexistnum=`ls $1.*.bad 2>/dev/null|wc -l |awk '{print $1}'`
	if [ $badexistnum -gt 0 ]
	then
		cat $1.????????.bad > $DIR/$1.bad.unl
		rm $1.????????.bad
		dbaccess ${fxdatabase}<<EOF 1>>$log 2>&1
		load from $DIR/$1.bad.unl insert into fx_$1;
EOF
		if [ $? = 0 ]
		then
			log4s info "${1} 失败重传导入成功"
			rm $DIR/$1.bad.unl
		else
			log4s error "${1} 失败重传导入失败"
			mv $DIR/$1.bad.unl $DIR/$1.$dt.bad
		fi
	fi
	#判断是否存在，存在则导入
	existnum=`ls $1.*.temp 2>/dev/null|wc -l |awk '{print $1}'`
	if [ $existnum -gt 0 ]
	then
		cat $1.????????.temp > $DIR/$1.unl
		rm $1.????????.temp
		dbaccess ${fxdatabase}<<EOF 1>>$log 2>&1
		load from $DIR/$1.unl insert into fx_$1;
EOF
		if [ $? = 0 ]
		then
			log4s info "${1} 导入成功"
			rm $DIR/$1.unl
		else
			log4s error "${1} 导入失败"
			mv $DIR/$1.unl $DIR/$1.$dt.bad
		fi
	else
		log4s info "${1} 不存在，无需导入"
	fi
}
loadandrmxn()
{
	#判断是否失败的，失败的一天导入一次
	#$1是文件主要名称，$2是目录
	cd $DIR;
	badexistnum=`ls $1.*.bad 2>/dev/null|wc -l |awk '{print $1}'`
	if [ $badexistnum -gt 0 ]
	then
		cat $1.????????.bad > $1.bad.unl
		rm $1.????????.bad
		dbaccess ${fxdatabase}<<EOF 1>>$log 2>&1
		load from $1.bad.unl insert into fx_$1;
EOF
		if [ $? = 0 ]
		then
			log4s info "${1} 失败重传导入成功"
			rm $1.bad.unl
		else
			log4s error "${1} 失败重传导入失败"
			mv $1.bad.unl $1.$dt.bad
		fi
	fi
	#判断是否存在，存在则导入
	existnum=`ls $1.log.??????????.temp 2>/dev/null|wc -l |awk '{print $1}'`
	if [ $existnum -gt 0 ]
	then
		cat $1.log.??????????.temp > $1.unl
		rm $1.log.??????????.temp
		log4s info "开始导入$1"
		dbaccess ${fxdatabase}<<EOF 1>>$log 2>&1
		load from $1.unl insert into fx_$1;
EOF
		if [ $? = 0 ]
		then
			log4s info "${1} 导入成功"
			rm $1.unl
		else
			log4s error "${1} 导入失败"
			mv $1.unl $1.$dt.bad
		fi
	else
		log4s info "${1} 不存在，无需导入"
	fi
}
loadfx()
{
	loadandrm sysdri
	loadandrm sysenv
	loadandrm machineinfo
	loadandrm sysshmvals
	loadandrm sysdatabases
	loadandrm sysprofile
	loadandrm syssegments
	loadandrm sysvplst
	loadandrm syschktab
	loadandrm sysdbspaces
	loadandrm syschunks
	loadandrm sysptprof
	loadandrm systables
	loadandrm sysindexes
	loadandrm syssessions
	loadandrm syssesprof
	loadandrm syslogs
	loadandrm syslogfil
	loadandrm sysconfig
	loadandrm syssqlhosts
	loadandrm sysfragments
	loadandrm systabinfo
	loadandrm hb_sqlite3_syschktab
	loadandrm hb_sqlite3_sysprofile
	loadandrm hb_sqlite3_sysptprof
	loadandrm hb_sqlite3_syssesprof
	loadandrm hb_sqlite3_syssessions
	loadandrm hb_sqlite3_sysvplst
}
if [ X$3 = Xperformance ]
then
	nohup sh $workdir/idsmon.sh $dbid $workdir top 1>$workdir/topnohup.out 2>&1 &
	nohup sh $workdir/idsmon.sh $dbid $workdir vmsar 1>$workdir/vmsarnohup.out 2>&1 &
elif [ X$3 = Xtop ]
then
	GetTop
elif [ X$3 = Xvmsar ]
then
	GetPerformance
elif [ X$3 = Xxnanalysis ]
then
	analysis "$2" "$3"
elif [ X$3 = Xupdate ]
then
	update_init "$1" "$2" "$3" "$4" "$5" "$6"
	update_cron_config "$1" "$2" "$3" "$4" "$5" "$6"
else
	if [ $1 = load ]
	then
		DIR=$2
		loadfx
	else
		frequency
	fi
fi
