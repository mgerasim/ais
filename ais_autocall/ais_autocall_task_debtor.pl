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

if (!@ARGV) {
    die "Укажите идентификатор задания\n";
}

my $taskid = $ARGV[0];
my $CONFIG = 'ais_autocall.cfg';
my $MODULE = "ais_autocall_task_asrdebtor_$taskid";

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
	
	if (DB_Report($conn, $taskid, $log)>0) {
	    $log->error("DB_Handler: Ошибка при формировании отчета статистики обзвона должников");
	    goto ERROR;
	}
	if (DB_Task($conn, $taskid, $log)>0) {
	    $log->error("DB_Handler: Ошибка при формировании задания на следующий месяц");
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

# Создает отчет статистики обзвона должников
# 0 - успешно
# 1 - не успешно
sub DB_Report
{
    my $conn = shift;
    my $id_task = shift;
    my $log = shift;
    my $res = 1;
    eval {
        my $stat_all;
	my $stat_ans;
	my $stat_nas;
	my $stat_bus;
	my $stat_pay;
	my $stat_lef;
	
	
	$log->debug("Получение имени задания");
	$task_name = AIS_UTIL_DB_Selectrow($conn,
				"SELECT ring_task_get_name_by_id($id_task)",
				$log);
	if (!defined($task_name)) {
		$log->error("Ошибка при получении имени задания");
		goto END;
	}

        $stat_all = AIS_UTIL_DB_Selectrow($conn,
	    "SELECT count(*) FROM call_numbers WHERE id_ring_task=$id_task",
	    $log );
	
	$stat_ans = AIS_UTIL_DB_Selectrow($conn,
	    "SELECT count(*) FROM call_numbers WHERE id_ring_task=$id_task AND call_status=7",
	    $log );
        $stat_nas = AIS_UTIL_DB_Selectrow($conn,
	    "SELECT count(*) FROM call_numbers WHERE id_ring_task=$id_task AND call_status=10",
	    $log );
	$stat_bus = AIS_UTIL_DB_Selectrow($conn,
	    "SELECT count(*) FROM call_numbers WHERE id_ring_task=$id_task AND call_status=11",
	    $log );
        $stat_pay = AIS_UTIL_DB_Selectrow($conn,
	    "SELECT count(*) FROM call_numbers WHERE id_ring_task=$id_task AND call_status=4",
	    $log );
	$stat_lef = AIS_UTIL_DB_Selectrow($conn,
	    "SELECT count(*) FROM call_numbers WHERE id_ring_task=$id_task AND call_status=1",
	    $log );
    
	my $ss = sprintf("%s", $task_name);
	my $message = <<__MESSAGE__;

*Отчет по информированию клиентов ОАО Дальсвязь о задолжности.

Общее количество - '$stat_all'
из них:
    Ответили - '$stat_ans'
    Не ответили - '$stat_nas'
    Занято - '$stat_bus'
    Задолжность оплачена - '$stat_pay'

    Осталось - '$stat_lef'


АВТООБЗВОН ДОЛЖНИКОВ
Разработчик:
    Герасимов Михаил Николаевич
    тел. : (4212) 322151
    email: GerasimovMN\@khv.dv.rt.ru
    
-------------------------
*Отчет формируется автоматически и ежемесячно после окончания выполнения задания
-------------------------
Имя задания: '$ss'
Идентификатор: '$id_task'
__MESSAGE__

    
	$log->debug("Отправка отчета");
        SendMail("GerasimovMN\@khv.dv.rt.ru", "Autocall\@t90.corp.fetec.dsv.ru", "Debtor $ss", $message);

	$res = 0;
    };
    if ($@) {
	$log->error("DB_Report: Ошибка выполнения: $@");
	goto END;
    }
    END:
    return $res;
}

# Создает задание обзвонки на следующий месяц
# 0 - успешно
# 1 - не успешно
sub DB_Task
{
    my $conn	= shift;
    my $taskid	= shift;
    my $log	= shift;
    my $res	= 1;
    eval {
	my $task_date = AIS_UTIL_DB_Selectrow($conn,
			"SELECT AIS_AUTOCALL_UTIL_MONTH()",
			$log);
	if (!defined($task_date)) {
	    $log->error("DB_Task: Ошибка определения параметра task_date");
	    goto END;
	}
	my $task_name = "DEBTOR $task_date";
	$log->debug("DB_Task: Создаем задание $task_name");
	
	my $query = sprintf("SELECT AIS_AUTOCALL_HANDLER_TASK_COPY(\n"
		."$taskid,"
		."'%s' \n"
		.")", $task_name);
	$log->debug("DB_Task: Запрос:\n$query");
	
	
	my $task_copy_id = AIS_UTIL_DB_Selectrow($conn, $query, $log);
	if (!defined($task_copy_id)) {
	    $log->error("DB_Task: Ошибка копирования задания $task_name");
	    goto END;
	}
	
	my $DAYBGN = AIS_UTIL_DB_Selectrow($conn,
			"SELECT link_task_prop_get_value($task_copy_id, 'DAYBGN')",
			$log);
	if (!defined($DAYBGN)) {
	    goto END;
	}
	
	my $DAYEND = AIS_UTIL_DB_Selectrow($conn,
			"SELECT link_task_prop_get_value($task_copy_id, 'DAYEND')",
			$log);
	if (!defined($DAYEND)) {
	    goto END;
	}
	
	my $TTNAME = AIS_UTIL_DB_Selectrow($conn,
			"SELECT link_task_prop_get_value($task_copy_id, 'TTNAME')",
			$log);
	if (!defined($TTNAME)) {
	    goto END;
	}
	
	$query = "UPDATE ring_task SET name_task='$task_name' WHERE id=$task_copy_id";
	my $upd = AIS_UTIL_DB_Do($conn, $query, $log);
	if (!defined($upd)) {
	    $log->error("DB_Task: Ошибка обновления имени задания");
	    goto END;
	}
	
	$upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($task_copy_id, task_property_get_id_by_name('DATEBEGIN'), '$task_date-$DAYBGN')",
			$log);
	if (!defined($upd)) {
	    goto END;
	}
	$upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($task_copy_id, task_property_get_id_by_name('DATEEND'), '$task_date-$DAYEND')",
			$log);
	if (!defined($upd)) {
	    goto END;
	}

	$upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($task_copy_id, task_property_get_id_by_name('PRECOMPL'), '0')",
			$log);
	if (!defined($upd)) {
	    goto END;
	}
	$upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($task_copy_id, task_property_get_id_by_name('POSTCOMPL'), '0')",
			$log);
	if (!defined($upd)) {
	    goto END;
	}

	$log->debug("DB_Task: Задание $task_name создано");
	my $message = <<__MESSAGE__;
Задание $task_name успешно создано на следующий месяц


АВТООБЗВОН ДОЛЖНИКОВ
Разработчик:
    Герасимов Михаил Николаевич
    тел. : (4212) 322151
    email: GerasimovMN\@khv.dv.rt.ru
    
-------------------------
*Отчет формируется автоматически и ежемесячно после окончания выполнения задания
-------------------------
__MESSAGE__

    
	$log->debug("Отправка отчета");
        SendMail("GerasimovMN\@khv.dv.rt.ru", "Autocall\@t90.corp.fetec.dsv.ru", "Debtor Notify", $message);
	
	
	$res = 0;
    };
    if ($@) {
	$log->error("DB_Task: Ошибка выполнения: $@");
	goto END;
    }
    END:
    return $res;
}

eval {
    $log->debug("Установка соединения $DB->{dbname}");
    my $upd = undef;
    # Устанавливаем соединение с БД для получения параметров соедиения с АСР СТАРТ
    my $conn = undef;
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
	goto END;
    }
    $log->debug("Соединение установлено $DB->{dbname}");
    
# Статус выполнения скрипта записывается в параметр POSTCOMPL в самом скрипте
# POSTCOMPL = 0 - скрипт не выполнялся
# POSTCOMPL = 1 - скрипт выполняется
# POSTCOMPL = 2 - скрипт выполнен успешно
# POSTCOMPL = 3 - во время выполнения скрипта произошла ошибка
# Задание переходит на обработку при POSTCOMPL=1
	

    $log->debug("Обновление параметра PRECOMPL после выполнения скрипта");
    $upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($taskid, task_property_get_id_by_name('POSTCOMPL' ), '1')",
			$log);
    if (!defined($upd)) {
	    $log->error("Ошибка обновление параметра POSTCOMPL после выполнения скрипта");
    }

    
    if (DB_Handler($conn, $taskid,  $log)>0) {
	$log->error("Ошибка при обработке DB_Handler");
	
	$log->debug("Обновление параметра POSTCOMPL после ошибочного выполнения скрипта");
	$upd = AIS_UTIL_DB_Do($conn,
			"SELECT link_task_prop_upd($taskid , task_property_get_id_by_name('POSTCOMPL' ), '3')", 
			$log);
        if (!defined($upd)) {
		    $log->error("Ошибка обновление параметра POSTCOMPL после ошибочного выполнения скрипта");
	}
    } else {    
        $log->debug("Обновление параметра POSTCOMPL после выполнения скрипта");
	$upd = AIS_UTIL_DB_Do($conn,
	    	    	"SELECT link_task_prop_upd($taskid, task_property_get_id_by_name('POSTCOMPL' ), '2')",
				$log);
        if (!defined($upd)) {
		    $log->error("Ошибка обновление параметра POSTCOMPL после выполнения скрипта");
	}
    }
    
    $log->debug("Разрыв соединения $DB->{dbname}");
    $conn->disconnect();
    $conn = undef;
};
if ($@) {
    $log->error("Фатальная ошибка: $@");
    die "Фатальная ошибка: $@";
}
END: