package AIS_CORE::Service;

BEGIN {
    print <STDOUT>, "Dsv2::Service::BEGIN";
}

use strict;
use warnings;
use threads;
use threads::shared;
use AIS_CORE::Log;
use Data::Dumper;

our @ISA = qw(AIS_CORE::Log);

sub new {
    my $invocant = shift; # первый параметр - ссылка на объект или имя класса
    my $class = ref($invocant) || $invocant; # получение имени класса
    my $data = { @_ }; # ссылка на анонимный хеш - это и будет нашим новым объектом, инициализация объекта
    die "Укажите имя сервиса: name" if (!defined($data->{name}));

    my $self = $invocant->SUPER::new(name=>$data->{name}, LOG_DIR=>$data->{LOG_DIR}, LOG_MIN_LEVEL=>$data->{LOG_MIN_LEVEL});
    $self->{log}->debug("Dsv::Service::new()");
    share($self->{keep_going});
    $self->{keep_going} = 1;

    return $self; # возвращаем объект
}

sub add {
    print "Service::add() \n";

    my $self = shift;
    my $module = shift;
    my $handle = shift;
    die "Укажите модуль для добавления в сервис" if (!defined($module));
    die "Укажите функцию-обработчик для модуля '$module->{name}'" if !defined $handle;
    $self->{log}->debug("Service::add()");
    $self->{log}->notice("Добавление модуля '$module->{name}' в сервис '$self->{name}'");

    share($module->{keep_going});
    my %Module = (
		    'Object' => $module,
		    'Handle' => $handle
		 );
		 
    push @{$self->{Modules}}, \%Module;
    $self->{log}->debug(Dumper($self->{Modules}));
}

sub Process
{
    print "Service::Process\n";
    my $self = shift;
    $self->{log}->debug("Service::Process()");
    my @Threads;
    die "Ошибка! Нет добавленных модулей!" if !defined($self->{Modules});
    my @Modules = @{$self->{Modules}};

    foreach my $Module (@Modules)
    {
	my $Handle = ${%{$Module}}{'Handle'};
	my $Object = ${%{$Module}}{'Object'};
	$self->{log}->debug("Service::Process: Запуск модуля '$Object->{name}'");
	push @{$self->{Threads}}, threads->create(\&$Handle);
    }

}

sub Join
{
    my $self = shift;
    $self->{log}->debug("Service::Join");
    my @Threads = @{$self->{Threads}};
    foreach my $thread (@Threads)
    {
	$thread->join();
    }
}

sub Stop
{
    print "Service::Stop\n";
    my $self = shift;
    $self->{log}->debug("Service::Stop");
    $self->{log}->debug(Dumper($self->{Modules}));
    my @Modules = @{$self->{Modules}};
    foreach my $Module (@Modules)
    {
	my $Object = ${%{$Module}}{'Object'};
	print "Service::Stop: Остановка модуля '$Object->{name}'";
	$self->{log}->debug("Service::Stop: Остановка модуля '$Object->{name}'");
	$Object->Stop();
	$self->{log}->debug($Object);
    }
    # Ожидание 
    $self->Join();
    print "Сервис остановлен\n";	
}

sub DESTROY
{
}


return 1;
