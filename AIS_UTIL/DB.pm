package AIS_UTIL::DB;

use strict;
use warnings;
use DBI;
use Data::Dumper;
use Email::Send;

our(@ISA, @EXPORT, $VERSION);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(AIS_UTIL_DB_SmartConnection AIS_UTIL_DB_Do AIS_UTIL_DB_Selectrow AIS_UTIL_DB_Execute);
$VERSION = "0.01";


# Функция для создания и проверки текущего соединения с БД
sub AIS_UTIL_DB_SmartConnection
{
    my $conn   ;
    my $dbhost ;
    my $dbport ;
    my $dbname ;
    my $login  ;
    my $pwd    ;
    my $log    ;
    
    eval {
    
        print "Functions::SmartConnection\n";

        $conn   = shift;
        $dbhost = shift;
        $dbport = shift;
        $dbname = shift;
	$login  = shift;
        $pwd    = shift;
	$log    = shift;
    
        $log->debug("Dsv2::Functions::SmartConnection");
    
	print "SmartConnection: Укажите параметр 'dbhost'" if !defined $dbhost;
	print "SmartConnection: Укажите параметр 'dbport'" if !defined $dbport;
        print "SmartConnection: Укажите параметр 'dbname'" if !defined $dbname;
	print "SmartConnection: Укажите параметр 'dbuser'"  if !defined $login;
	print "SmartConnection: Укажите параметр 'dbpass'"    if !defined $pwd;
	print "SmartConnection: Укажите параметр 'log'"    if !defined $log;
    
	if (defined($conn)) 
	{
	    my $query = "SELECT 1";
	    my $rw = $conn->do($query) or die "Ошибка! Не удалось выполнить тестовый запрос! $DBI::errstr\n";
	    if (!defined($rw))
	    {
		print ("Dsv::Functions::SmartConnection: Ошибка при выполнении тестового запроса '$query'\nКод $DBI::err Описание: $DBI::errstr");
		$log->error("Dsv::Functions::SmartConnection: Ошибка при выполнении тестового запроса '$query'\nКод $DBI::err Описание: $DBI::errstr");
		print ("Dsv::Functions::SmartConnection: Разрыв текущего соединения");
		$log->debug("Dsv::Functions::SmartConnection: Разрыв текущего соединения");
		$conn->disconnect();
		$conn = undef;
	    }
	}
	if (!defined($conn))
	{
	    $conn = DBI->connect("dbi:Pg:dbname=$dbname;host=$dbhost","$login","$pwd", {PrintError => 0});
	    $log->debug("Dsv::Functions::SmartConnection: Соединние с БД: dbname=$dbname, host=$dbhost, login=$login");
	    if (defined($conn->err()))
	    {
		print "Dsv::Functions::SmartConnection: Ошибка соединения: Код: $conn->err() $conn->errstr()";
		$log->error("Dsv::Functions::SmartConnection: Ошибка соединения: Код: $conn->err() $conn->errstr()");
		$conn=undef;
	    } 
	    else {
		$log->debug("Dsv::Functions::SmartConnection: Коннект '$dbname' успешно создан");
	    } 
	}
    };
    if ($@) {
	$log->error("Dsv::Functions::SmartConnection: Неизвестная ошибка");
	$conn = undef;
    }
    return $conn;

}

# Функция выполняет запрос без возвращения записей из БД
sub AIS_UTIL_DB_Do
{
    my $conn = shift;
    my $query = shift;
    my $log = shift;
    my $error ;
    my $result = undef;

    eval {
	$log->debug("Dsv::Functions::Do: Выполнение запроса: '$query'");
	my $rw = $conn->do($query);
	if (!defined $rw) {
	    $error = "При выполнении запроса '$query' возникла ошибка:\n$DBI::errstr";
	    $log->error($error);
	    goto END;
	}
	$result = 1;
    };
    if ($@) {
	$error = "Dsv::Functions::Do: Неизвестная ошибка";
	$log->error("$error");
	goto END;
    }
    END:
    return $result;
}

# Функция возвращает значение поля таблицы
sub AIS_UTIL_DB_Selectrow
{
    my $conn 	= shift;
    my $query 	= shift;
    my $log 	= shift;
    my $error 	= "";  
    my $rw = undef;
    
    eval {
	$log->debug("Dsv::Functions::Selectrow: Выполнение запроса '$query'");
	$rw = $conn->selectrow_array($query);
	if (defined($rw)) {
	    $log->debug("Dsv::Functions::Selectrow: Результат: '$rw'");
	} else {
	    $log->debug("Dsv::Functions::Selectrow: Результат: none");
	}
	
	
    };
    if ($@) {
	$error = "Dsv::Functions::Selectrow: Неизвестная ошибка: $@";
	$log->error("$error");
	goto END;
    }
    END:
    return $rw;
}


sub AIS_UTIL_DB_Execute
{
    my ($conn, $query, $log) = @_;
    my $sth = undef;
    my $error;
    my $result= 0;

    eval {
	$sth = $conn->prepare($query);
	$log->debug("Dsv::Functions::Execute: Запрос: '$query'");
	my $rw = $sth->execute();
	if (!defined($rw)) {
	    $error = "При выполнении запроса '$query' возникла ошибка:\n$DBI::errstr";
	    $log->error($error);
	    $sth = undef;
	    goto END;
	}
	$log->debug("AIS_UTIL: Результат: $DBI::rows");
	$result = 1;
    };
    if ($@) {
	$error = "AIS_UTIL: Неизвестная ошибка";
	$log->error($error);
	$sth = undef;
	goto END;
    }
    END:

    return $sth;
}

return 1;