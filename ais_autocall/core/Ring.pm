package core::Ring;

BEGIN {

        push @INC,"/usr/proj/AIS";
}

use strict;
use AIS_UTIL::DB;
use AIS_UTIL::Functions;
use AIS_CORE::Subservice;
use AIS_RING::ASRSTART;
use Data::Dumper;

our @ISA = qw(AIS_CORE::Subservice);

sub new
{
    my $invocant = shift; # первый параметр - ссылка на объект или имя класса
    my $class = ref($invocant) || $invocant; # получение имени класса
    my $self = $invocant->SUPER::new(@_);
    return $self; # возвращаем объект
}

sub Handler
{
    my $self = shift;
    $self->{log}->debug("Autocall::Ring::Handler()");
    my $data = { @_ };
    my $DB = $data->{DB};
    my $LIMIT = $data->{RING_LIMIT};
    if (!defined $LIMIT) {
        $self->{log}->error("Укажите количество записей отбираемых для обзвона: парметр RING_LIMIT");
        return ;
    }
    die "Неопределен $self->{log}" if (!defined($self->{log}));
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
	my $result=undef;
	$sth = AIS_UTIL_DB_Execute($conn, 
		"SELECT * FROM AIS_AUTOCALL_SELECT_RING($LIMIT)",
		$self->{log});
	if (!defined($sth)) {
	    $self->{log}->error("Autocall::Ring::Handler: Ошибка выполнения функции 'Execute'");
	    goto END;
	}
	
	while (my $ring = $sth->fetchrow_hashref())
	{
	    $self->{log}->debug("Autocall::Ring::Handler: Обрабатываем тел.: '$ring->{'phone_number'}' id='$ring->{'id'}'");
	    $self->{log}->debug("voice_file: '$ring->{'voice_file'}' voice_text: '$ring->{'voice_text'}'");
	    
	    $self->{log}->debug("Autocall::Ring::Handler: Устанавливаем статус ЗВОНИМ");
	    my $query = "UPDATE call_numbers SET call_status=6  WHERE id=$ring->{'id'}";
	    $result = AIS_UTIL_DB_Do($conn, $query, $self->{log});
	    if ($result==0) {
		$self->{log}->error("Autocall::Ring::Handler: Функция 'Do' вернула ошибку");
		next;
	    }
	    
	    if (AIS_IsDefined($ring->{'voice_file'})) {
		AIS_wav2gsm($ring, $self->{log});
		AIS_Call($ring, "/ru/$ring->{'voice_file'}", $self->{log});
		next;
	    }
	    elsif (AIS_IsDefined($ring->{'voice_text'})) {
		AIS_txt2wav($ring, $self->{log});
		AIS_Call($ring, "/ru/$ring->{'id'}", $self->{log});
		next;
	    }
	    my $asrstart = AIS_UTIL_DB_Selectrow($conn, "SELECT link_task_prop_get_value($ring->{'id_ring_task'}, 'ASRSTART')", $self->{log});
	    if (!defined($asrstart)) {
		$self->{log}->error("Ошибка при определении параметра ASRSTART");
		next;
	    }
	    if ($asrstart == 1) {
		$self->{log}->debug("Определяем задолжность из системы АСР СТАРТ");
		if (AIS_RING_ASRSTART_Handler($conn, $ring, $self->{log})>0) {
		    $self->{log}->error("Ошибка при обработки вызова во внешней системе АСР СТАРТ");
		    next;
		}
	    }
	    
	}
	$sth->finish();


    };
    if ($@) {
	$self->{log}->error("Autocall::Ring::Handler::Блок обработки исключений:Неизвестная ошибка: $@");
    }
    END:
}

return 1;

END {}