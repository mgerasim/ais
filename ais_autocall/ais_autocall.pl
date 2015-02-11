#!/usr/bin/perl


BEGIN {

        push @INC,"/usr/proj/AIS";
        
                }

use strict;
use warnings;
use lib '/usr/proj/AIS';
use lib '/usr/proj/AIS/ais_autocall';
use Proc::Daemon;
use Proc::PID::File;
use XML::Simple;
use POSIX qw(setsid EWOULDBLOCK);
use core::Task;
use core::Ring;
use AIS_CORE::Service;

my $MODULE="ais_autocall";

$_=$MODULE;
my $pidfile = "/var/run/$MODULE.pid";
my $CONFIG = "$MODULE.cfg";
my $is_daemonized = 0;

#
# Функция переводит работу скрипта в режим демон-процесса
#
sub daemonize()
{
	$is_daemonized = 1;
	defined( my $pid = fork ) or die "Can't Fork: $!";
        exit if $pid;
	setsid or die "Can't start a new session: $!";
        open MYPIDFILE, ">$pidfile"
	      or die "Failed to open PID file $pidfile for writing.";
        print MYPIDFILE $$;
	close MYPIDFILE;

        close(STDIN);
        
}

# Получаем команду СТОП и завершаем процесс
if (@ARGV && $ARGV[0] eq "stop")
{
    my $pid = Proc::PID::File->running(name => $MODULE);
    unless ($pid)
    { print "Процесс не запущен!\n" }

    # Убиваем процесс
    kill(2,$pid);  # you may need a different signal for your system
    print "Получен СТОП сигнал!\n";
    exit;
}

# Получаем команду СТАТУС
if (@ARGV && $ARGV[0] eq "status")
{
    my $pid = Proc::PID::File->running(name => $MODULE);
    if ($pid==0)
    {
	print "Процесс не запущен!\n" 
    }
    else
    {
	print "Процесс запущен!\n";
    }
    exit;
}


if (Proc::PID::File->running(name => $MODULE))
{
    print "Процесс уже запущен";
    exit 0;
}


# Запуск в режиме демон-процесс
if (@ARGV && $ARGV[0] eq "daemon")
{
    daemonize();
}


# Чтение конфигурации
my $config = XML::Simple->new()->XMLin($CONFIG);

my $LOG_DIR		= $config->{LOG_DIR};
my $LOG_FILE   		='$MODULE.log';
my $LOG_MIN_LEVEL	= $config->{LOG_MIN_LEVEL};
# Connection
my $DB;
$DB->{dbhost}		= $config->{pg_dbhost};
$DB->{dbport}		= $config->{pg_dbport};
$DB->{dbname}		= $config->{pg_dbname};
$DB->{dbuser} 		= $config->{pg_dblogin};
$DB->{dbpass}  		= $config->{pg_dbpasswd};
# XML шлюз
my $XML_host 		= $config->{XML_host};
my $XML_port 		= $config->{XML_port};

my $TASK_SLEEP		= $config->{TASK_SLEEP};
my $RING_SLEEP		= $config->{RING_SLEEP};
my $RING_LIMIT		= $config->{RING_LIMIT};
#ASR START Oracle Connection
my $ORACLE_SID		= $config->{oracle_sid};
my $ORACLE_USERID	= $config->{oracle_userid};
my $ORACLE_PASSWORD	= $config->{oracle_password};

#
# Главный сервис
#
my $Service = new AIS_CORE::Service(name=>$MODULE, 
				LOG_DIR=>$LOG_DIR,
				LOG_FILE=>$LOG_FILE,
				LOG_MIN_LEVEL=>$LOG_MIN_LEVEL);
				
my $Task = new core::Task(MODULE=>"$MODULE-task",
			    SLEEP_TIME=>$TASK_SLEEP,
			    LOG_DIR=>$LOG_DIR,
			    LOG_MIN_LEVEL=>$LOG_MIN_LEVEL);

my $Ring = new core::Ring(MODULE=>"$MODULE-ring",
			    SLEEP_TIME=>$RING_SLEEP,
			    XML_port=>$XML_port,
			    XML_host=>$XML_host,
			    LOG_DIR=>$LOG_DIR,
			    LOG_MIN_LEVEL=>$LOG_MIN_LEVEL);

$Service->add($Task, sub {  $Task->Process(DB=>$DB); });
$Service->add($Ring, sub {  $Ring->Process(DB=>$DB, 
			    RING_LIMIT=>$RING_LIMIT); });



#
#  Установка обработчиков сигнала завершения процесса
#
my $keep_going = 1;
$SIG{HUP}  =  sub { $Service->Stop(); $keep_going = 0; };
$SIG{INT}  =  sub { $Service->Stop(); $keep_going = 0; };
$SIG{QUIT} =  sub { $Service->Stop(); $keep_going = 0; };

my $logdir="/usr/proj/AIS/$MODULE";

$Service->Process();

while ($keep_going==1)
{
    my $cmd=" ";
    if ($is_daemonized==0)    {
        $cmd = <STDIN>;
        chomp $cmd;
    }
    
    if ($cmd eq "exit") {
	$keep_going = 0;
    }
    if ($cmd eq "err") {
	die "D";
    }
    if ($cmd eq "daemon") {
    
	if ( $logdir ne "" ) {
	    open( STDOUT, ">>$logdir/output.log" )
    		or die "Can't open output log $logdir/output.log";
	    open( STDERR, ">>$logdir/error.log" )
    		or die "Can't open output log $logdir/error.log";
	}
	daemonize();
	if ( $logdir eq "" ) {
	    close STDOUT;
	    close STDERR;
	}
    }

    if ($cmd eq "stop") {
	$Service->Stop();
    }
    $cmd=" ";
}