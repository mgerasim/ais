package AIS_CORE::Log;

use strict;

use Log::Dispatch;
use Log::Dispatch::File;
use Date::Format;
use File::Spec;

sub new 
{
    my $invocant = shift; # первый параметр - ссылка на объект или имя класса
    my $class = ref($invocant) || $invocant; # получение имени класса
    my $self = { @_ }; # ссылка на анонимный хеш - это и будет нашим новым объектом, инициализация объекта
    bless($self, $class); # освящаем ссылку в объект
    
    die "Укажите имя лог-файла: name"  if (!defined($self->{name})) ;
    die "Укажите директорию логирования: LOG_DIR" if (!defined($self->{LOG_DIR}));
    die "Укажите уровень логирования: LOG_MIN_LEVEL" if (!defined($self->{LOG_MIN_LEVEL}));

    # Устанавливаем логирование
    our $HOSTNAME = `hostname`;
    chomp $HOSTNAME;
    $self->{log} = new Log::Dispatch(
        callbacks => sub { my %h=@_; return Date::Format::time2str('%B %e %T', time)." ".$HOSTNAME." $0\[$$]: ".$h{message}."\n"; }
        );
        $self->{log}->add( Log::Dispatch::File->new( 	name      => 'file1',
    		    min_level => $self->{LOG_MIN_LEVEL},
    		    mode      => 'append',
    		    filename  => File::Spec->catfile($self->{LOG_DIR}, $self->{name}.".log"),
    	    )
    	);
    return $self; # возвращаем объект
}

return 1;
