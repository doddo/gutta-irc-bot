package Gutta::Plugins::Ibood;
# does something with Ibood

use parent Gutta::Plugin;
use LWP::Simple;
use HTML::TokeParser;

sub process_msg
{
    my $self = shift;
    my $msg = shift;
    my $nick = shift;
    my $mask = shift;
    my $target = shift;


    if ($msg =~ /^\s*!ibood/)
    { 
       return "msg $target " . $self->ibood();
    } else { 
       return undef;
    }
}

sub ibood
{
    my $self = shift;
    my $url = "http://ibood.com/be/nl/";
    my $html = get($url);
    my $parser = HTML::TokeParser->new(\$html);
    my ($title, $price) = 0;
    while ( my $token = $parser->get_tag("a") )
    {
        if ($token->[1]{id} and ($token->[1]{id} eq "link_product"))
        {
            $title = $parser->get_trimmed_text;
            last;
        }
    }
    $parser = HTML::TokeParser->new(\$html);
    while ( my $token = $parser->get_tag("span") )
    {
        if ($token->[1]{class} and ($token->[1]{class} eq "price"))
        {
            $parser->get_tag("span");
            $price = $parser->get_text;
            last;
        }
    }
    return "iBood: $title. (\x{20AC}$price) $url";
}

1;
