#!/usr/bin/perl

BEGIN {
    push @INC,"/usr/proj/AIS";
}

use strict;
use warnings;
use lib '/usr/proj/AIS';
use lib '/usr/proj/AIS/ais_autocall';
use XML::Simple;
use POSIX qw(setsid EWOULDBLOCK);
use Log::Dispatch;
use Log::Dispatch::File;
use Date::Format;
use File::Spec;
use DBI;
use AIS_UTIL::Functions;
use AIS_UTIL::DB;



my $debug = 0;
my $count = 0; # количество загруженных записей, используется для отсылки отчета
my $task_name = "";
my $ora = undef;

if (!@ARGV) {
    die "Укажите идентификатор задания\n";
}

my $taskid = $ARGV[0];
my $CONFIG = 'ais_autocall.cfg';
my $MODULE = "ais_autocall_task_asrloader_$taskid";

# Чтение конфигурации
my $config = XML::Simple->new()->XMLin($CONFIG);

my $LOG_DIR		= $config->{LOG_DIR};
my $LOG_FILE   		="$MODULE.log";
my $LOG_MIN_LEVEL	= $config->{LOG_MIN_LEVEL};
# Connection
my $DB;
$DB->{dbhost}		= $config->{pg_dbhost};
$DB->{dbport}		= $config->{pg_dbport};
$DB->{dbname}		= $config->{pg_dbname};
$DB->{dbuser} 		= $config->{pg_dblogin};
$DB->{dbpass}  		= $config->{pg_dbpasswd};

# Устанавливаем логирование
our $HOSTNAME = `hostname`;
chomp $HOSTNAME;
my $log = new Log::Dispatch(
    callbacks => sub { my %h=@_; return Date::Format::time2str('%B %e %T', time)." ".$HOSTNAME." $0\[$$]: ".$h{message}."\n"; }
    );

$log->add( Log::Dispatch::File->new( 	name      => 'file1',
	    min_level => $LOG_MIN_LEVEL,
	    mode      => 'append',
	    filename  => File::Spec->catfile($LOG_DIR, $LOG_FILE),
    )
);


# 0 - успешно
# 1 - ошибка
sub DB_Handler
{
    my $conn = shift;
    my $taskid = shift;
    my $log = shift;
    my $error = "";
    
    my $res2 = 1;
    eval {
	$log->debug("Получение имени задания");
	$task_name = AIS_UTIL_DB_Selectrow($conn,
				"SELECT ring_task_get_name_by_id($taskid)",
				$log);
	if (!defined($task_name)) {
		$error = "Ошибка при получении имени задания";
		$log->error("Ошибка при получении имени задания");
		goto ERROR;
	}
	
    
	my $asrsql = AIS_UTIL_DB_Selectrow($conn, 
				"SELECT H_GET_TASK_PROPERTY($taskid, 'SQLQUERY')",
				$log);
	if (!defined($asrsql)) {
		$log->error("Ошибка при получении запроса к АСР СТАРТ");
		die "Ошибка при получении запроса к АСР СТАРТ";
		goto ERROR;
        }
	$log->debug("Получили запрос к АСР СТАРТ:\n$asrsql");
    
    
        my $asrsid = AIS_UTIL_DB_Selectrow($conn, 
				"SELECT H_GET_TASK_PROPERTY($taskid, 'ASRSID')",
				$log);
	if (!defined($asrsid)) {
		$log->error("Ошибка при получении SID АСР СТАРТ");
		die "Ошибка при получении SID  АСР СТАРТ";
		goto ERROR;
        }
	$log->debug("Получили SID АСР СТАРТ:\n$asrsid");
    
	my $asruid = AIS_UTIL_DB_Selectrow($conn, 
				"SELECT H_GET_TASK_PROPERTY($taskid, 'ASRUID')",
				$log);
        if (!defined($asruid)) {
		$log->error("Ошибка при получении USER IDк АСР СТАРТ");
		die "Ошибка при получении USER ID АСР СТАРТ";
		goto ERROR;
	}
        $log->debug("Получили USER ID  АСР СТАРТ:\n$asruid");
    
    
    
        my $asrpwd = AIS_UTIL_DB_Selectrow($conn, 
				"SELECT H_GET_TASK_PROPERTY($taskid, 'ASRPWD')",
				$log);
	if (!defined($asrpwd)) {
		$log->error("Ошибка при получении PWD к АСР СТАРТ");
		die "Ошибка при получении PWD к АСР СТАРТ";
		goto ERROR;
        }
	$log->debug("Получили PWD к АСР СТАРТ:\n$asrpwd");

        if (ASR_Loader($conn, $taskid, $asrsid, $asruid, $asrpwd, $asrsql, $log)>0) {
    		$error = "Ошибка при работе с АСР СТАРТ";
    		$log->error($error);
    		goto ERROR;
        }
        
        $res2 = 0;
	return $res2;
    };
    if ($@) {
	$error = "DB_Handler: Фатальная ошибка: $@";
	$log->error($error);
	goto ERROR;
    }
    ERROR:
    return $res2;
}

# 0 - успешно
# 1 - ошибка
sub ASR_Loader
{
    my $conn   = shift;
    my $taskid = shift;
    my $asrsid = shift;
    my $asruid = shift;
    my $asrpwd = shift;
    my $asrsql = shift;
    my $log	= shift;
    my $res = 1;
    my $strerr = "";
    eval {
	$log->debug("ASR_Loader: Установка соединения с АСР СТАРТ");
	$ora = DBI->connect("DBI:Oracle:$asrsid", "$asruid", $asrpwd, {AutoCommit => 0, PrintError=>1});
    if (!defined($ora)) {
	$log->error("Ошибка установления соединения с АСР СТАРТ");
	die "Ошибка установления соединения с АСР СТАРТ";
	goto END;
    }
    $log->debug("Соединение с АСР СТАРТ успешно установлено");
    
    eval {
	# Выполняем запрос к АСР СТАРТ
	
	$asrsql = "SELECT '4212322151' as PHONE FROM DUAL" if $debug==1;
	
	my $ora_sth = $ora->prepare($asrsql);
	
	if ($DBI::err) {
	    $log->error("ASR_LOADER_2: ERROR: $DBI::errstr");
	    $strerr = $DBI::errstr;
	    $log->debug("ASR_LOADER_2: return");
	    goto END_2;
	}
	
	$log->debug("ASR_Loader: Выполнение запроса:\n$asrsql");
	my $ora_rw = $ora_sth->execute();
	if (!defined($ora_rw)) {
	    $log->error("ASR_Loader_2: Ошибка выполнения запроса: $DBI::errstr");
	    $strerr = $DBI::errstr;
	    goto END_3;
	}
	
	$count = 0;
	while (my $phone = $ora_sth->fetchrow_hashref()) {
	    $count = $count + 1;
	    $log->debug("ASR_Loader: Добавляем номер $phone->{PHONE}");
	    my $status = AIS_UTIL_DB_Do($conn,
				"SELECT G_ADD_PHONE_NUMBER_TO_TASK($taskid, '$phone->{PHONE}')",
				$log);
	    if (!defined($status)) {
		$log->error("ASR_Loader: Ошибка вставки номера");
		next;
	    }
	}
	END_3:
	$ora_sth->finish();
	END_2:
	
    };
    if ($@) {
	$log->error("ASR_Loader_2: Фатальная ошибка: $@");
	$strerr = $@;
    } 
    
	$log->debug("Разрыв соединения с АСР СТАРТ");
	$ora->disconnect();
	$ora = undef;
	if ($strerr ne "") {
	    goto END;
	}
	$res = 0;


    };
    if ($@) {
	$log->error("ASR_Loader: Фатальная ошибка: $@");
    }
    END:
    return $res;
}

my $conn = undef;

$SIG{HUP}  =  sub { $conn->disconnect() if defined $conn; $ora->disconnect() if defined $ora; };
$SIG{INT}  =  sub { $conn->disconnect() if defined $conn; $ora->disconnect() if defined $ora; };
$SIG{QUIT} =  sub { $conn->disconnect() if defined $conn; $ora->disconnect() if defined $ora; };


eval {
    $log->debug("eval bgn");
    $log->debug("Установка соединения $DB->{dbname}");
    my $upd = undef;
    # Устанавливаем соединение с БД для получения параметров соедиения с АСР СТАРТ
    $conn = AIS_UTIL_DB_SmartConnection($conn,
				$DB->{dbhost}, 
				$DB->{dbport},
				$DB->{dbname},
				$DB->{dbuser},
				$DB->{dbpass},
				$log);
				
    if (!defined($conn))
    {
	$log->error("Ошибка соединения $DB->{name}");
	die "Ошибка соединения $DB->{dbname}" ;
    }
    $log->debug("Соединение установлено $DB->{dbname}");

# Статус выполнения скрипта записывается в параметр PRECOMPL в самом скрипте
# PRECOMPL = 0 - скрипт не выполнялся
# PRECOMPL = 1 - скрипт выполняется
# PRECOMPL = 2 - скрипт выполнен успешно
# PRECOMPL = 3 - во время выполнения скрипта произошла ошибка
# Задание переходит на обработку при PRECOMPL=1
	
    $log->debug("Обновление параметра PRECOMPL после выполнения скрипта");
    $upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($taskid, task_property_get_id_by_name('PRECOMPL' ), '1')",
			$log);
    if (!defined($upd)) {
	    $log->error("Ошибка обновление параметра PRECOMPL после выполнения скрипта");
    }

    if (DB_Handler($conn, $taskid,  $log)>0) {
	$log->error("Ошибка при обработке DB_Handler");
	
	$log->debug("Обновление параметра PRECOMPL после ошибочного выполнения скрипта");
	$upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($taskid , task_property_get_id_by_name('PRECOMPL' ), '3')", 
			$log);
        if (!defined($upd)) {
		    $log->error("Ошибка обновление параметра PRECOMPL после ошибочного выполнения скрипта");
	}
    } else {    
        $log->debug("Обновление параметра PRECOMPL после выполнения скрипта");
	$upd = AIS_UTIL_DB_Do($conn,
	    	    	"SELECT link_task_prop_upd($taskid, task_property_get_id_by_name('PRECOMPL' ), '2')",
				$log);
        if (!defined($upd)) {
		    $log->error("Ошибка обновление параметра PRECOMPL после выполнения скрипта");
	}
    }

    $log->debug("Разрыв соединения $DB->{dbname}");
    $conn->disconnect();
    $conn = undef;
    
my $message = <<__MESSAGE__;
* Отчет о зогрузки задания 
Имя: $task_name
№ $taskid

Количество добавленных номеров: $count

Разработчик:
    Герасимов Михаил Николаевич
    тел. : (4212) 322151
    email: GerasimovMN\@khv.dsv.ru
    
-------------------------
*Отчет формируется автоматически и ежемесячно после окончания выполнения задания
-------------------------
__MESSAGE__

    $log->debug("Отправка отчета");
    SendMail("GerasimovMN\@khv.dv.rt.ru", "Autocall\@t90.corp.fetec.dsv.ru", "Report", $message);
};
if ($@) {
    $log->error("Фатальная ошибка: $@");
    die "Фатальная ошибка: $@";
}
$log->debug("undef");
$log = undef;
$config = undef;