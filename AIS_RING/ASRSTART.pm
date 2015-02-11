package AIS_RING::ASRSTART;

use strict;
use warnings;
use Data::Dumper;
use AIS_UTIL::DB;
use AIS_UTIL::Functions;
use Socket;

our(@ISA, @EXPORT, $VERSION);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(AIS_RING_ASRSTART_Handler AIS_RING_ASRSTART_saldo2wav);
$VERSION = "0.01";


# Функция обрабатывает параметры вызова
sub AIS_RING_ASRSTART_Handler
{
    my $res = 1;
    my $conn   = shift;
    my $ring   = shift;
    my $log    = shift;
    my $upd;
    eval {
	$log->error("AIS_RING_ASRSTART_Handler: Обрабатываем телефонный номер: $ring->{'phone_number'}");
	my $xmlhost = AIS_UTIL_DB_Selectrow($conn, "SELECT link_task_prop_get_value($ring->{'id_ring_task'}, 'XMLHOST')", $log);
	if (!defined($xmlhost)) {
	    $log->error("Ошибка получения параметра XMLHOST");
	    goto END;
	}
	my $xmlport = AIS_UTIL_DB_Selectrow($conn, "SELECT link_task_prop_get_value($ring->{'id_ring_task'}, 'XMLPORT')", $log);
	if (!defined($xmlport)) {
	    $log->error("Ошибка получения параметра XMLPORT");
	    goto END;
	}
	my $abonent_hash = AIS_RING_ASRSTART_XMLRequest($ring->{'phone_number'}, $xmlhost, $xmlport, $log);

	if (!defined($abonent_hash)) {
	    $log->error("AIS_RING_ASRSTART_Handler: Ощибка при XML запрос/ответ");
	    goto END;
	}

	if (AIS_RING_ASRSTART_IsEmptyXML($abonent_hash, $log)){
	    $log->debug("Проверка доступности АСР СТАРТ");
	    if (AIS_RING_START_Ping($xmlhost, $xmlport, $log)) {
		$log->warning("АСР СТАРТ не доступент");
		$res = 0;
		goto END;
	    }
	    $log->debug("АСР СТАРТ доступен");
	    $log->debug("Выставляем статус для вызова Пустой");
	    $upd = AIS_UTIL_DB_Do($conn,
			    "UPDATE call_numbers SET call_status=3 WHERE id=$ring->{'id'}",
			    $log);
	    if (!defined($upd)) {
		$log->error("Ошибка при обновлении статуса вызова на ПУСТОЙ");
		goto END;
	    }  
	}
	my $vendors = ($abonent_hash->{balance}->{vendor});
	my $DSV_vendor = 0; 
	if (defined ($vendors->{id})) {
	    $DSV_vendor = $vendors;
	} 
	else
	{
	    while ( (my $key, my $vendor) = each %$vendors)
	    {
    		if ($vendor->{id}==1)
    		{
    		    $DSV_vendor = $vendor;
    		}

	    }
    	}
    	#Присваиваем остаток
    	$log->debug("DUMP: dumper($DSV_vendor->{previos_month_saldo}");
    	
    	if (!AIS_IsDefined($DSV_vendor->{previos_month_saldo})) {
    	    $DSV_vendor->{previos_month_saldo} = 0;
    	}
    	if (!AIS_IsDefined($DSV_vendor->{current_month_saldo})) {
    	    $DSV_vendor->{current_month_saldo} = 0;
    	}
    	
        $log->debug("Присваиваем остаток по Дальсвязи previos_month_saldo = $DSV_vendor->{previos_month_saldo}, current_month_saldo = $DSV_vendor->{current_month_saldo}");
        $_ = $DSV_vendor->{previos_month_saldo};
        s/,/./;
        if (!AIS_IsDefined($_)) {
    	    $_ = '0.0';
        }
        my $previos_month_saldo = int($_*100); # остаток на начало месяца, если <0 то задолжность
        $_ = $DSV_vendor->{current_month_pays};
        s/,/./;
        if (!AIS_IsDefined($_)) {
    	    $_ = '0.0';
        }
        $log->debug("___ = $_ ");
        my $current_month_pays = int($_*100); # сумма платежей в текущем платежей
        $ring->{'saldo'} = $previos_month_saldo + $current_month_pays;
        $upd = AIS_UTIL_DB_Do($conn, "UPDATE call_numbers SET saldo=$ring->{'saldo'} WHERE id=$ring->{'id'}", $log);
        if (!defined($upd)) {
	    $log->error("Ошибка при обновлении задолжности");
	    goto END;
        }
	$log->debug("RING_chkdebt: Получен баланс: $ring->{'saldo'}");
	$log->debug("RING_chkdebt: Определяем статус клиента (ОПЛАЧЕН/НЕ ОПЛАЧЕН) ...");
	# Готовим запрос на выборку параметра DEBTLMT - лимит задолжности
	my $debtlmt = AIS_UTIL_DB_Selectrow($conn,
				    "SELECT H_GET_TASK_PROPERTY($ring->{'id_ring_task'}, 'DEBTLMT')",
				    $log);
	if (!defined($debtlmt)) {
	    $log->error("Ошибка при получении параметра DEBTLMT - лимит задолжности");
	    goto END;
	}
	# Сравниваем баланс с границей задолжности и проставляем статус
	if ($ring->{'saldo'}>int($debtlmt)*(-1))
	{
	    $ring->{'call_status'} = 4; # оплачен
	    $log->debug("RING_chkdebt: Статус клиента: ОПЛАЧЕН (4)");
	    
	    $upd = AIS_UTIL_DB_Do($conn,
			    "UPDATE call_numbers SET call_status=4 WHERE id=$ring->{'id'}",
			    $log);
	    if (!defined($upd)) {
		$log->error("Ошибка при обновлении статуса вызова на ОПЛАЧЕН");
		goto END;
	    } 
	    goto END;
	}
	# Далее работаем с телефонными номерами со статусом НЕ ОПЛАЧЕН (5)
	# Получаем список файлов для произношения баланса клиента от ОАО Дальсвязь
	my $asterisk_playdata = AIS_RING_ASRSTART_saldo2wav($ring, $log);
	AIS_Call($ring, $asterisk_playdata, $log);
	
	$res = 0;
    };
    if ($@) {
	$log->error("ASR_RING_ASRSTART_Handler: Неизвестная ошибка: $@");
    }
    END:
    return $res;

}


# При получении пустого номера от XML шлюза, посылаем тестовый служебный номер и если от XML шлюза ответ пустой
# то делаем вывод, что АСР СТАРТ не доступен
sub AIS_RING_ASRSTART_Ping
{
    my $xmlhost = shift;
    my $xmlport = shift;
    my $log 	= shift;
    eval {
	my $test_phone = '4212322151';
	my $abonent_hash = AIS_RING_ASRSTART_XMLRequest($xmlhost, $xmlport, $log);
	if (!defined($abonent_hash)) {
	    $log->error("AIS_RING_ASRSTART: Ошибка при определении доступности АСР СТАРТ");
	    return 0;
	}
	if (AIS_RING_ASRSTART_IsEmptyXML($abonent_hash)) {
	    return 0;
	}
	return 1;
    };
    if ($@) {
	$log->error("AIS_RING_ASRSTART: Неизвестная ошибка: $@");
    }
    return 0;
}


# Функция получает хеш абонента и проверяет пустой ли он
sub AIS_RING_ASRSTART_IsEmptyXML
{
    my $abonent_hash = shift;
    my $log = shift;
    $log->debug("AIS_RING_ASRSTART_IsEmptyXML");
    # Проверка на ошибочный номер телефона
    foreach my $err (keys %$abonent_hash) {
	if ($err eq "error") {
	    return 1;
	}
    }
    return 0;
}

sub AIS_RING_ASRSTART_XMLRequest
{
    my $phone_number = shift;
    my $xmlhost = shift;
    my $xmlport = shift;
    my $log = shift;
    my $res = undef;
    my ($key, $abonent_hash);
    eval {
	$log->debug("AIS_RING_ASRSTART_XMLRequest: Создание сокета: host=$xmlhost port=$xmlport");
	my $request_xml = '<?xml version="1.0" encoding="CP1251" ?>'    
	        .'<request>'	    	        
    	        .'<abonent phone="'.$phone_number.'" />'	    	    	    	        
    	        .'</request>'	    	    	    	    	    	        
	    	."\r\n+++\r\n";	
	    	
        #Сокет для установления связи
	socket(SOCK_M31, PF_INET, SOCK_STREAM, getprotobyname('tcp'))   or  die "При установлении связи с сервером, возникла ошибка : $!\n"; 
        $log->debug("Успешное создание сокета");
        
        my $iaddr = inet_aton($xmlhost);
	my $internet_addr = gethostbyname($xmlhost) or die "Couldn't convert $xmlhost into an Internet address: $!\n";
	my $paddr = sockaddr_in($xmlport, $iaddr);
	# Устанавливаем соединение
	connect(SOCK_M31, $paddr) or die "Couldn't connect to $xmlhost:$xmlport : $!\n";

	$log->debug("Успешное соединение с $xmlhost:$xmlport");
	# Отправляем запрос на получение данных о пользователе по его номеру
        send (SOCK_M31, $request_xml, 0); 
	$log->debug("Отправили запрос: $request_xml");
        # Ответ
	my $answer="";    
        my @answer_array;
	# Построчно считываем ответ от сервера
        while (defined($answer=<SOCK_M31>) && (substr($answer,0,3) cmp "+++")!=0 ) {
		# Помещаем в массив
    	    push @answer_array, $answer;    
	}
	# Полученный массив  строк объединяем в одну строку
	my $answer_xml = join("", @answer_array);
        $log->debug("Получили ответ:");
	$log->debug($answer_xml);
    
        # Парсим формат XML представленный в виде строки
	$log->debug("Парсим формат XML представленный в виде строки");
        my $xs = XML::Simple->new();
	my $ref_hash = $xs->XMLin($answer_xml);
    
        ($key, $abonent_hash) = each %$ref_hash; 
	$log->debug("-> $abonent_hash");
    };
    if ($@) {
	$log->error("ASR_RING_ASRSTART_XMLRequest: Неизвестная ошибка: $@");
    }
    END:
    return $abonent_hash;
}


my $DSV_sound = "/ru/";
# Данные значения переопределяются в main()
my $DSV_phrase_bgn = "Prompt2222";
my $DSV_phrase_end = "";

my $ONE_HUNDRED 	=100;
my $ONE_THOUSAND	=1000;
my $ONE_MILLION		=1000000;
my $ONE_BILLION		=1000000000;

my @ru_num_phrases = (["10^3-1","10^3-2","10^3-5"], 
		  ["10^6-1","10^6-2","10^6-5"],
		  ["1rub",  "2rub",  "5rub"  ],
		  ["1cop",  "2cop",  "5cop"  ]);


sub ru_get_index 
{
my $n = $_[0];

if ($n % $ONE_HUNDRED >= 11 && $n % $ONE_HUNDRED <= 14)
{
    return 2;
}

my $e = $n % 10;
if ($e == 1) {
    return 0;
} 
elsif ($e==2 || $e==3 || $e== 4) {
    return 1;
} 
else {
    return 2;
} # if
    
} # ru_get_index


# Формат вызова create_wav_number(254, "rub"); - составляет список файлов "254 рубля"
sub create_wav_number
{
    my $res = 0;
    
    (my $num, my $manye, my $ref_data_wav) = @_;
    
    while (!$res && $num) {
	my $fn = "";
	if ($num < 20)
	{
	    if ($num==1 || $num==2) {
		if ($manye eq "") {
		    $manye = "l";
		}
		$fn = "$num$manye";
	    } 
	    else {
		$fn = "$num";
	    }
	    $num = 0;
	} 
	elsif ($num < $ONE_HUNDRED) {
	    my $tmp = $num - ($num % 10);
	    $fn = "$tmp";
	    $num %= 10;
	}
	elsif ($num < $ONE_THOUSAND) {
	    my $tmp = $num - ($num % $ONE_HUNDRED);
	    $fn = "$tmp";
	    $num %= $ONE_HUNDRED;
	}
	elsif ($num < $ONE_MILLION) {
	    my $digits = int ($num / $ONE_THOUSAND);
	    $res = create_wav_number($digits, "", $ref_data_wav);
	    if ($res) {return $res; }
	    $fn = "$ru_num_phrases[0][ru_get_index($digits)]";
	    $num %= $ONE_THOUSAND;	    
	} elsif ($num < $ONE_BILLION) {
	    my $digits = int ($num / $ONE_MILLION);
	    $res = create_wav_number($digits, "g", $ref_data_wav);
	    if ($res) {return $res; }
	    $fn = "$ru_num_phrases[1][ru_get_index($digits)]";
	    $num %= $ONE_MILLION;
	}
	else {
	    print "Заданное число $num слишком большое для меня\n";
	    $res = -1;
	    return $res;
	}
	#print "->>>$fn\n";
	if ($fn ne ""){
	    push(@$ref_data_wav, "$DSV_sound$fn");
	}
    } #while
    return $res;
}# create_wav_number


# Функция получает значение остатка saldo 
# и формирует строку из wav файлов
sub AIS_RING_ASRSTART_saldo2wav
{
    my $call_number = shift;
    my $log = shift;
    $log->warning("Входим в функцию wav_saldo_full_play_data: saldo = $call_number->{'saldo'}");
    my $saldo = abs($call_number->{'saldo'});
    chomp $saldo;
    	{
		my $rub = int(substr($saldo,0, length($saldo)-2));
		my $cop = int(substr($saldo, length($saldo)-2, length($saldo)));
		
		$log->warning("$rub руб. $cop коп.");
		
		my @data_wav;
		my $res;
		
		push(@data_wav, "$DSV_sound$DSV_phrase_bgn");
		
		$res = create_wav_number($rub, "g", \@data_wav);
		if ($res<0) {
		$log->warning("Ошибка при разборе рублей");
		}
		
		if ($rub==0) {
		my $tmp = "0";
		
		push(@data_wav, "$DSV_sound$tmp");
		}
		
		push(@data_wav, "$DSV_sound$ru_num_phrases[2][ru_get_index($rub)]");
		
		if ($cop) {
			$res = create_wav_number($cop, "l", \@data_wav);
			if ($res<0) {
			print "Ошибка при разборе копеек\n";
		}
		push(@data_wav,  "$DSV_sound$ru_num_phrases[3][ru_get_index($cop)]");
		}
		
		push(@data_wav, "$DSV_sound$DSV_phrase_end");
		
		foreach my $str (@data_wav) {
		$log->warning("->$str");
		}
		
		my $play_data = join("&", @data_wav);
		return $play_data;
	}
		
}

return 1;