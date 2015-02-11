package AIS_CORE::Subservice;

use strict;
use AIS_CORE::Log;
use Data::Dumper;
use threads;

our @ISA = qw(AIS_CORE::Log);

sub new
{
    my $invocant = shift; # первый параметр - ссылка на объект или имя класса
    my $class = ref($invocant) || $invocant; # получение имени класса
    my $data = { @_ };
    die "Укажите имя модуля: MODULE" if (!defined($data->{MODULE}));
    die "Укажите время повтора выполнения модуля: SLEEP_TIME" if !defined $data->{SLEEP_TIME};
    $data->{LOG_DIR}='/var/log' if (!defined($data->{LOG_DIR}));
    $data->{LOG_MIN_LEVEL} = 'debug' if (!defined($data->{LOG_MIN_LEVEL}));
    my $self = $invocant->SUPER::new(name=>$data->{MODULE}, LOG_DIR=>$data->{LOG_DIR}, LOG_MIN_LEVEL=>$data->{LOG_MIN_LEVEL});
    $self->{log}->debug("Subservice::new");
    $self->{SLEEP_TIME} = $data->{SLEEP_TIME};

    $self->{keep_going} = 1;
    return $self; # возвращаем объект
}


sub Handler
{
    # Заглушка
    # Переопределяется потомками
}

sub Process
{
    print "Subservice::Process\n";
    my $self = shift;
    $self->{log}->debug( "Dsv::Subservice::Process: Работа модуля '$self->{name}' начало выполнения");
    $self->{keep_going} = 1;
    while($self->{keep_going})
    {
        $self->{log}->debug( "Dsv::Subservice::Process() while keep_going=$self->{keep_going}");
	$self->Handler(@_);
	my $i=0;
	while ($i<$self->{SLEEP_TIME} and $self->{keep_going}) {
	    $i++;
	    sleep(1);
	}
    }
    $self->{log}->debug( "Subservice::Process: Работа модуля '$self->{name}' остановлена");
}

sub SleepTime
{
    my $self = shift;
    return $self->{SLEEP_TIME};
}

sub Stop
{
    print "Subservice::Stop\n";
    my $self = shift;
    $self->{log}->debug(ref($self));
    $self->{log}->debug("Subservice::Stop: '$self->{name}'");
    $self->{log}->debug("keep_going=$self->{keep_going}");
    $self->{keep_going} = 0;
    $self->{log}->debug("keep_going=$self->{keep_going}");
}

sub DESTROY
{
}

return 1;
