package core::Task;

BEGIN {}

use strict;
use warnings;
use AIS_CORE::Subservice;
use AIS_UTIL::DB;
use AIS_UTIL::Functions;
use Data::Dumper;
use threads;

our @ISA = qw(AIS_CORE::Subservice);

sub new
{
    my $invocant = shift; # первый параметр - ссылка на объект или имя класса
    my $class = ref($invocant) || $invocant; # получение имени класса
    my $data = { @_ };
    my $self = $invocant->SUPER::new(@_);
    $self->{log}->debug("Autocall::Task");
    $self->{Subthreads} = undef;
    $self->{Subname} = undef;
    $self->{conn}=undef;
    return $self; # возвращаем объект
}

sub Run
{
    my $runstr = shift;
    qx($runstr);
}

sub Handler
{
    my $self = shift;
    $self->{log}->debug("Autocall::Task::Handler");
    die "Ошибка! Нет параметров!\n" 			if (!defined({@_}));
    my $data = { @_ };
    
    die "Ошибка! Не определена переменная DB!\n" 	if (!defined($data->{DB}));
    
    my $DB = $data->{DB};
    
    die "Ошибка! Не определена переменная dbhost!\n" 	if (!defined($DB->{dbhost}));
    die "Ошибка! Не определена переменная dbport!\n" 	if (!defined($DB->{dbport}));
    die "Ошибка! Не определена переменная dbname!\n" 	if (!defined($DB->{dbname}));
    die "Ошибка! Не определена переменная dbuser!\n" 	if (!defined($DB->{dbuser}));
    die "Ошибка! Не определена переменная dbpass!\n" 	if (!defined($DB->{dbpass}));

    my $conn=$self->{conn};
    
    eval {	

	$conn = AIS_UTIL_DB_SmartConnection($conn, 
				$DB->{dbhost}, 
				$DB->{dbport},
				$DB->{dbname},
				$DB->{dbuser},
				$DB->{dbpass},
				$self->{log});
	$self->{conn}=$conn;
	my $sth;
	my $result=1;
	$sth = AIS_UTIL_DB_Execute($conn, 
		"SELECT * FROM AIS_AUTOCALL_SELECT_TASK()",
		$self->{log});
	
	if (!defined($sth)) {
	    $self->{log}->error("Task::Handler: Ошибка выполнения функции 'Execute'\n ");
	    goto END;
	}
	
	while (my $task = $sth->fetchrow_hashref())
	{	
	    $self->{log}->debug("Autocall::Task::Handler: Обрабатываем задание: id='$task->{'id'}' name='$task->{'name_task'}'");
	    
	    # Запуск предворительного скрипта 
	    my $pretask = AIS_UTIL_DB_Selectrow($conn,
				"SELECT link_task_prop_get_value($task->{'id'}, 'PRETASK')",
				$self->{log});
	    if (AIS_IsDefined($pretask)) {
		$self->{log}->debug("Указан начальный скрипт: $pretask");
		
		$self->{log}->debug("Определяем флаг выполнения скрипта");
		my $precompl = AIS_UTIL_DB_Selectrow($conn,
				"SELECT link_task_prop_get_value($task->{'id'}, 'PRECOMPL')",
				$self->{log});
		if(!AIS_IsDefined($precompl)) {
		    $self->{log}->error("Ошибка! Для задания не указан параметр PRECOMPL");
		    next;
		}
		
		if ($precompl==0) {
		# Выполняем скрипт
		
			my $diff = AIS_UTIL_DB_Selectrow($conn,
					"SELECT (ais_autocall_util_timestamp_diff(ais_autocall_handler_task_datetime_bgn($task->{'id'})))",
					$self->{log});
			if (!defined($diff)) {
			    $self->{log}->error("Ошибка при опрелении разницы времени");
			    next;
			}
			$self->{log}->debug("Разница времени: $diff");
			# 0 - время загрузки
			if ($diff == 0) {
			    $self->{log}->debug("Выполнения начального скрипта");
			    my $runstr = "/usr/bin/perl /usr/proj/AIS/ais_autocall/$pretask $task->{id}";
			    $self->{log}->debug("Выполнение $runstr");
			    Run($runstr);
			}
			# Статус выполнения скрипта записывается в параметр PRECOMPL в самом скрипте
			# PRECOMPL = 0 - скрипт не выполнялся
			# PRECOMPL = 1 - скрипт выполняется
			# PRECOMPL = 2 - скрипт выполнен успешно
			# PRECOMPL = 3 - во время выполнения скрипта произошла ошибка
			# Задание переходит на обработку при PRECOMPL=1
			
			next;
		}
		
		if ($precompl==1) {
		    # Скрипт выполняется
		    $self->{log}->debug("Для задания выполняется скрипт начальной загрузки");
		    next;
		}
	    
		if ($precompl==2) {
		    $self->{log}->debug("Скрипт успешно отработал, переходим на обработку задания");
		    
		    $self->{log}->debug("Обновляем статус задания на ОЖИДАНИЕ");
		    my $upd =AIS_UTIL_DB_Do($conn, 
				"SELECT AIS_AUTOCALL_TASK_ACCEPT_LOAD_END($task->{'id'})",
				$self->{log});
		    if (!defined($upd)) {
			$self->{log}->error("Ошибка при обновлении задания на статус ОЖИДАНИЕ");
			next;
		    }
        
	        }
	    
		if ($precompl==3) {
		    # Во время выполнения скрипта начальной загрузки произошла ошибка
		    $self->{log}->debug("Обновление параметра PRECOMPL - запускаем скрипт заново");
		    my $upd = AIS_UTIL_DB_Do($conn,
					"SELECT link_task_prop_upd($task->{'id'}, task_property_get_id_by_name('PRECOMPL' ), '0')",
					$self->{log});
		    if (!defined($upd)) {
		        $self->{log}->error("Ошибка обновление параметра PRECOMPL после выполнения скрипта");
		    }
		    next;
		} 
	    } 
	
	    
	    
	    # Выполнение обзвона
	    my $res = AIS_UTIL_DB_Do($conn,
				"SELECT AIS_AUTOCALL_HANDLER_TASK($task->{'id'})",
				$self->{log});
	    if (!defined($res)) {
		$self->{log}->error("Task::Handler: При выполнении запроса 'SELECT H_CHECK_TASK_STATUS($task->{'id'})' возникла ошибка");
		next;
	    } 	
	    $self->{log}->debug("Успешное выполнение запроса 'SELECT H_CHECK_TASK_STATUS($task->{'id'})'");
	    
	    # Запуск завершающего скрипта
	    my $posttask = AIS_UTIL_DB_Selectrow($conn,
				"SELECT link_task_prop_get_value($task->{'id'}, 'POSTTASK')",
				$self->{log});
	    if (AIS_IsDefined($posttask)) {
		$self->{log}->debug("Указан начальный скрипт: $posttask");
		$self->{log}->debug("Определяем флаг выполнения скрипта");
		my $postcompl = AIS_UTIL_DB_Selectrow($conn,
				"SELECT link_task_prop_get_value($task->{'id'}, 'POSTCOMPL')",
				$self->{log});
		if(!AIS_IsDefined($postcompl)) {
		    $self->{log}->error("Ошибка! Для задания не указан параметр POSTCOMPL");
		    next;
		}
		
		if ($postcompl == 0) {
		    # Выполняем скрипт
		
		    my $diff = AIS_UTIL_DB_Selectrow($conn,
				"SELECT (ais_autocall_util_timestamp_diff(ais_autocall_handler_task_datetime_end($task->{'id'})))",
				$self->{log});
		    if (!defined($diff)) {
		        $self->{log}->error("Ошибка при опрелении разницы времени");
		        next;
		    }
		    $self->{log}->debug("Разница времени: $diff");
		    # 1 - время загрузки
		    if ($diff == 0) {
		        $self->{log}->debug("Выполнения начального скрипта");
		        my $runstr = "/usr/bin/perl /usr/proj/AIS/ais_autocall/$posttask $task->{id}";
		        $self->{log}->debug("Выполнение $runstr");
		        qx($runstr);
		    }
		    # Статус выполнения скрипта записывается в параметр PRECOMPL в самом скрипте
		    # POSTCOMPL = 0 - скрипт не выполнялся
		    # POSTCOMPL = 1 - скрипт выполняется
		    # POSTCOMPL = 2 - скрипт выполнен успешно
		    # POSTCOMPL = 3 - во время выполнения скрипта произошла ошибка
		    # Задание переходит на обработку при POSTCOMPL=1
		
		    next;
		} # $postcompl == 0
		
		if ($postcompl==1) {
		    # Скрипт выполняется
		    $self->{log}->debug("Для задания выполняется скрипт начальной загрузки");
		    next;
		}
	    
		if ($postcompl==2) {
		    $self->{log}->debug("Скрипт успешно отработал, переходим на обработку задания");
		    
		    $self->{log}->debug("Обновляем статус задания на ВЫПОЛНЕНА");
		    my $upd =AIS_UTIL_DB_Do($conn, 
				"SELECT AIS_AUTOCALL_TASK_ACCEPT_HANDLE_END($task->{'id'})",
				$self->{log});
		    if (!defined($upd)) {
			$self->{log}->error("Ошибка при обновлении задания на статус ВЫПОЛНЕНА");
			next;
		    }
        
	        }
	    
		if ($postcompl==3) {
		    # Во время выполнения скрипта начальной загрузки произошла ошибка
		    $self->{log}->debug("Обновление параметра POSTCOMPL - запускаем скрипт заново");
		    my $upd = AIS_UTIL_DB_Do($conn,
					"SELECT link_task_prop_upd($task->{'id'}, task_property_get_id_by_name('POSTCOMPL' ), '0')",
					$self->{log});
		    if (!defined($upd)) {
		        $self->{log}->error("Ошибка обновление параметра POSTCOMPL после выполнения скрипта");
		    }
		    next;
		} 
		
	    } # AIS_IsDefined
	}
	$sth->finish();
    };
    if ($@) {
	$self->{log}->debug("Autocall::Task::Handler: Блок обработки исключений: Неизвестная ошибка: $@");
    }
    END:
    return 0;
}


return 1;

END {}