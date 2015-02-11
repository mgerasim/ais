################################################################################################################################################
# Задача	Дата		Автор			Описание
# A0001 	2011-04-07 	Михаил Герасимов 	Устанавливать группу владельца asterisk для файла вызова
#
################################################################################################################################################


package AIS_UTIL::Functions;

use strict;
use warnings;
use DBI;
use Data::Dumper;
use Email::Send;

our(@ISA, @EXPORT, $VERSION);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(AIS_Call ParsePhoneNumber SendSMS SendMail AIS_IsDefined AIS_txt2wav AIS_wav2gsm);
$VERSION = "0.01";


# Формирует файл-вызова Asterisk
sub AIS_Call
{
    my $call_number = shift;
    my $play_data = shift;
    my $log = shift;
    $log->debug("create_asterisk_call: id='$call_number->{'id'}', play_data='$play_data'");

    # Каталоги asterisk
    my $ast_outgoing="/var/spool/asterisk/outgoing";
    my $ast_tmp="/var/spool/asterisk/tmp";
    my $ast_tmp_full="$ast_tmp/$call_number->{'id'}.call";

    my $phone_number = $call_number->{'phone_number'};

    #Формирование call-файл во временной папке
    if (!open(ASTERISK_TMP_FILE, ">$ast_tmp_full"))
    {
	$log->error("Ошибка при создании файла '$ast_tmp_full'\n");
	exit(0);
    }
    
#    $phone_number = '4212322151';
    
my $call_body = <<BODY;
Channel: SIP/CISCO_AS5400/8$phone_number
Callerid: 320320 
MaxRetries: $call_number->{'maxretries'}
RetryTime: $call_number->{'retrytime'}
WaitTime: $call_number->{'waittime'}
Application: Playback
Data: $play_data
Context: phones 
Extension: 
Priority: $call_number->{'priority'}
Account: $call_number->{'id'} 
BODY
    print ASTERISK_TMP_FILE $call_body;
    close (ASTERISK_TMP_FILE);
    
    $log->debug("Call: Выполнение chmod 666 $ast_tmp_full");
    qx(chmod 666 $ast_tmp_full);
    
    $log->debug("Call: Выполнение chown 100, 101, $ast_tmp_full");
    qx(chown asterisk $ast_tmp_full);
    qx(chgrp asterisk $ast_tmp_full);
    
    #Переместили call-файл для Asterisk
    qx(mv $ast_tmp_full $ast_outgoing);

    $log->debug("Файл вызова:\n$call_body");
}# create_asterisk_call

# Функция выделяет номер мобильного телефона из произвольной строки телефонных номер
sub ParsePhoneNumber
{
    my $contact_phone 	= shift;
    my $log		= shift;
    my $mobile_phone="";
    eval {
	
	$log->debug("DISLYSEND_mobilephone: Вход в функцию: contact_phone=$contact_phone");
	$_ = $contact_phone;
	 s/-//g;
	$log->debug("DISLYSEND_mobilephone: Преобразование: contact_phone=$_");
	/(9\d{9})/;
	$mobile_phone = $1;
	if (defined($mobile_phone)) {
	    $mobile_phone = "7$mobile_phone";
	    $log->debug("DISLYSEND_mobilephone: Выделен номер '$mobile_phone'");
	} else {
	    $mobile_phone = "";
	    $log->debug("DISLYSEND_mobilephone: Мобильный телефон не найден");
	}
    };
    if ($@) {
	$log->error("DISLYSEND_mobilephone: Неизвестная ошибка");
    }
    return $mobile_phone;
}

# Функция отправки SMS
sub SendSMS
{
    my $phone = shift;
    my $msg   = shift;
    
    qx(/usr/proj/smsinform/test/sendsms.pl $phone "$msg");
}

# Функция отправки E-mail сообщения
sub SendMail
{
    my $To = shift;
    my $From = shift;
    my $Subject = shift;
    my $Message = shift;
    my $message = <<__MESSAGE__; 
To: $To
From: $From
Subject: $Subject
Content-type:text/plain; charset = utf-8


$Message
__MESSAGE__

    my $mailer = Email::Send->new({mailer => 'SMTP'});
    $mailer->mailer_args([Host => '172.30.1.200']);
    $mailer->send($message);
}


# true - переменая содержит значение
sub AIS_IsDefined
{
    my $value = shift;
    my $result = 0;
    if (defined $value) {
        $result=1 if ($value ne "");
    }
    return $result;
}


# Функция AIS_wav2gsm
# Конвертирует файл в поле voice_file таблицы ring_task в формат gsm
sub AIS_wav2gsm
{
    my $ring = shift;
    my $log  = shift;
    my $ru = "/ru";
    eval {
        my $wav = "$ru/$ring->{'voice_file'}.wav";
	my $gsm = "$ru/$ring->{'voice_file'}.gsm";
	if (-e $wav) {
	    if (-e $gsm) {
	    }
	    else {
		qx(sox $wav -r 8000 -c 1 $gsm );
	    }
	}
	else {
	    $log->debug("AIS_wav2gsm: Файл '$wav' отсутствует");
	}
    };
    if ($@) {
	$log->error("AIS_wav2gsm: Ошибка выполнения:\n$@");
    }
    
}

# Функция AIS_txt2wav
# Конвертирует текст в поле voice_text таблицы ring_task в формат gsm
sub AIS_txt2wav
{
    my $ring = shift;
    my $TMP = "/tmp";
    my $txt = "$TMP/$ring->{'id'}.txt";
    my $wav = "$TMP/$ring->{'id'}.wav";
    my $gsm = "$TMP/$ring->{'id'}.gsm";
    
    if (!open(TXT_FILE, ">$txt")) {
	return 0;
    }
    my $txt_body = <<BODY;
$ring->{'voice_text'}
BODY

    print TXT_FILE $txt_body;
    close (TXT_FILE);
    qx(/usr/src/festival/bin/text2wave $txt -o $wav -eval '(voice_msu_ru_nsh_clunits)' );
    qx(sox $wav -r 8000 -c 1 $gsm resample -ql);
    qx(mv $gsm /ru/);
}



return 1;

