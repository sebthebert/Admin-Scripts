#!/usr/bin/env perl

=head1 NAME

zabbix_save_graphs.pl

=head1 DESCRIPTION

Saves PNG Graph pictures from Zabbix Web Interface

=head1 SYNOPSIS

zabbix_save_graphs.pl --url <zabbix_url> --login <login> --password <password> 
    [--screen <screen name>|--graph_list <graph_list_file>] [--period] 
    [--mail_src mail_src_address] [--mail_dest mail_dest_address] 
    [--debug]

=head1 OPTIONS

=over 2

=item B<-h, --help>       

Prints this Help

=item B<-u, --url>

URL of the Zabbix Web interface

=item B<-l, --login>

Login to connect to Zabbix Web interface

=item B<-p, --password>     

Password to connect to Zabbix Web interface

=item B<--screen>        

Screen from where you want to get pictures

=item B<--graph_list>

File which contains list of graphs to get

Lines in this file should be formatted like this: 

Group[<groupname>]:Host[<hostname>]:Graph[<graphtitle>]

=item B<--period>

Period (in seconds)

Default value 86400 (1 day). You can also use d/day/w/week/m/month words.

=item B<--mail_src>

Email address of the sender

=item B<--mail_dest>

Email address(es) where you want to send graphs

Could be "someone@domain.com" or coma separated addresses list "a1@domain.com,a2@domain.com"

=back

=head1 EXAMPLES

zabbix_save_graphs.pl --url http://127.0.0.1 --login me --password pwd --graph_list list.conf --period 1w

zabbix_save_graphs.pl --url http://127.0.0.1 --login me --password pwd --screen 'my awesome screen' --period 1month --mail_src zabbix@mydomain.org --mail_dest me@mydomain.org,someone@mydomain.org

=cut

use strict;
use warnings;
use Readonly;

use Getopt::Long;
Getopt::Long::Configure('bundling');
use Pod::Usage;

use HTML::TreeBuilder;
use Mail::Sender;
use WWW::Mechanize;

Readonly my $MAIL_SUBJECT => 'Zabbix Graphs';
Readonly my $MAIL_MESSAGE => 'Zabbix Graphs';
Readonly my $SMTP_SERVER  => '127.0.0.1';
Readonly my $TREE_GROUPID => '0.1.6.0.1.0.0.1.0.4';
Readonly my $TREE_HOSTID  => '0.1.6.0.1.0.0.1.0.6';
Readonly my $TREE_GRAPHID => '0.1.6.0.1.0.0.1.0.8';

our $VERSION = '0.9.3';

my ($opt_debug, $opt_help, $opt_url, $opt_login, $opt_password, $opt_graph_list,
    $opt_screen, $opt_period)
    = (undef, undef, undef, undef, undef, undef, undef, undef);
my ($opt_mail_src, $opt_mail_dest) = (undef, undef);

my %group_id    = ();
my %host_id     = ();
my %graph_id    = ();
my %graph_title = ();

my %period_letter = (
    'd'     => 86_400,
    'day'   => 86_400,
    'w'     => 604_800,
    'week'  => 604_800,
    'm'     => 2_592_000,
    'month' => 2_592_000,
);

my $mech = WWW::Mechanize->new();

=head1 FUNCTIONS

=head2 Debug(@args)

Prints Debug message

=cut

sub Debug
{
    my @args = @_;

    printf(@args) if (defined $opt_debug);

    return (undef);
}

=head2 Group_Ids

Generates Hash %group_id (groupname -> groupid)

=cut

sub Group_Ids
{
    Debug("Getting Group Ids...\n");
    $mech->get("$opt_url/charts.php");
    $mech->submit_form(form_id => 'node_form', fields => {groupid => 0});
    my $tree           = HTML::TreeBuilder->new_from_content($mech->content());
    my $selector_group = $tree->address($TREE_GROUPID);
    my $html           = $selector_group->as_HTML;
    %group_id = ($html =~ / title="(.+?)" value="(\d+)"/g);

    return (undef);
}

=head2 Host_Ids

Generates Hash %host_id (hostname -> hostid)

=cut

sub Host_Ids
{
    my $groupid = shift;

    Debug("Getting Host Ids...\n");
    $mech->get("$opt_url/charts.php");
    $mech->submit_form(fields => {groupid => $groupid});
    my $tree           = HTML::TreeBuilder->new_from_content($mech->content());
    my $selector_group = $tree->address($TREE_HOSTID);
    my $html           = $selector_group->as_HTML;
    %host_id = ($html =~ / title="(.+?)" value="(\d+)"/g);

    return (undef);
}

=head2 Graph_Ids

Generates Hash %graph_id (graphtitle -> graphid)

=cut

sub Graph_Ids
{
    my ($groupid, $hostid) = @_;

    Debug("Getting Graph Ids...\n");
    $mech->get("$opt_url/charts.php");
    $mech->submit_form(fields => {groupid => $groupid, hostid => $hostid});
    my $tree           = HTML::TreeBuilder->new_from_content($mech->content());
    my $selector_group = $tree->address($TREE_GRAPHID);
    my $html           = $selector_group->as_HTML;
    %graph_id = ($html =~ / title="(.+?)" value="(\d+)"/g);
    foreach my $k (keys %graph_id)
    {
    	my $value = $graph_id{$k};
    	delete $graph_id{$k};
    	$k =~ s/&amp;/&/g;
    	$graph_id{$k} = $value;
    }

    return (undef);
}

=head2 Graph_Titles

Generates Hash %graph_title (graphid -> graphtitle)

=cut

sub Graph_Titles
{
    Debug("Getting Graphs Titles...\n");
    $mech->get("$opt_url/charts.php");
    $mech->submit_form(fields => {groupid => 0, hostid => 0});
    my $tree           = HTML::TreeBuilder->new_from_content($mech->content());
    my $selector_graph = $tree->address($TREE_GRAPHID);
    my $html           = $selector_graph->as_HTML;
    while ($html =~ / title="(.+?)" value="(\d+)"/g)
    {
        $graph_title{$2} = $1;
    }

    return (undef);
}

=head2 Save_Graph_PNG($filename, $data)

Saves PNG Graph data '$data' into file '$filename'

=cut

sub Save_Graph_PNG
{
    my ($filename, $data) = @_;

    if (defined open my $out, '>', $filename)
    {
        print {$out} ${$data};
        close $out;
    }
    else
    {
        printf("[ERROR] Unable to write file '$filename'\n");
    }

    return (-s $filename);
}

=head2 Save_Graphs_From_Screen

Save Graphs from Screen

=cut

sub Save_Graphs_From_Screen
{
    my $period   = shift;
    my @graphs   = ();
    my $nb_graph = 1;

    Graph_Titles();
    Debug("Going to 'Screen' page...\n");
    die "[ERROR] Unable to going to 'Screen' page"
        if (!defined $mech->follow_link(text => 'Screens'));

    Debug("Selecting Screen '%s'...\n", $opt_screen);
    my $content = $mech->content();
    my ($screen_id) = ($content =~ /<option value="(\d+)" title="$opt_screen"/);

    Debug("Screen: '$opt_screen' -> $screen_id\n");
    $mech->submit_form(fields => {elementid => $screen_id});

    my @links = $mech->find_all_links(url_regex => qr/charts\.php\?graphid=/);
    foreach my $l (@links)
    {
        my $graph_url = $l->url();
        my ($gid) = ($graph_url =~ /charts\.php\?graphid=(\d+)/);
        $graph_url =~ s/charts\.php/chart2\.php/;
        $graph_url =~ s/period=(\d+)/period=$period/;
        Debug("Link: %s -> %s -> %s\n", $gid, $graph_title{$gid}, $graph_url);
        $mech->get("$opt_url/$graph_url");
        my $data = $mech->content();
        Save_Graph_PNG("graph_${opt_screen}_${nb_graph}.png", \$data);
        push @graphs, "graph_${opt_screen}_${nb_graph}.png";
        $nb_graph++;
    }

    return (\@graphs);
}

=head2 Save_Graphs_From_List

=cut

sub Save_Graphs_From_List
{
    my $period = shift;
    my @graphs = ();

    Group_Ids();
    my ($last_groupname, $last_hostname) = ('', '');
    if (defined open my $file_list, '<', $opt_graph_list)
    {
        while (<$file_list>)
        {
            if ($_ =~ /^Group\[(.+?)\]:Host\[(.+?)\]:Graph\[(.+?)\]/)
            {
                my ($groupname, $hostname, $graphtitle) = ($1, $2, $3);

                if (defined $group_id{$groupname})
                {
                    Host_Ids($group_id{$groupname}) if ($last_groupname ne $groupname);
                    $last_groupname = $groupname;
                    if (defined $host_id{$hostname})
                    {
                        Graph_Ids($group_id{$groupname}, $host_id{$hostname}) if ($last_hostname ne $hostname);
                        $last_hostname = $hostname;
                        if (defined $graph_id{$graphtitle})
                        {
                            my ($groupid, $hostid, $graphid) = (
                                $group_id{$groupname}, $host_id{$hostname},
                                $graph_id{$graphtitle},
                            );
                            Debug("Graph => %s / %s / %s\n",
                                $groupname, $hostname, $graphtitle);
                            $mech->get("$opt_url/charts.php");
                            $mech->submit_form(
                                fields => {
                                    groupid => $groupid,
                                    hostid  => $hostid,
                                    graphid => $graphid,
                                }
                            );
                            $mech->get(
"$opt_url/chart2.php?graphid=${graphid}&period=${period}"
                            );
                            my $data = $mech->content();
                            Save_Graph_PNG(
"graph_${groupname}_${hostname}_${graphtitle}.png",
                                \$data
                            );
                            push @graphs,
"graph_${groupname}_${hostname}_${graphtitle}.png";
                        }
                        else
                        {
                            printf("[ERROR] Unknown Graph '$graphtitle'\n");
                        }
                    }
                    else
                    {
                        printf("[ERROR] Unknown Host '$hostname'\n");
                    }
                }
                else
                {
                    printf("[ERROR] Unknown Group '$groupname'\n");
                }
            }
        }
        close $file_list;
    }
    else
    {
        printf("[ERROR] Unable to open graphs list '$opt_graph_list'\n");
    }

    return (\@graphs);
}

=head2 MAIN

=cut

my $status = GetOptions(
    'h|help'       => \$opt_help,
    'u|url=s'      => \$opt_url,
    'l|login=s'    => \$opt_login,
    'p|password=s' => \$opt_password,
    'graph_list=s' => \$opt_graph_list,
    'screen=s'     => \$opt_screen,
    'period=s'     => \$opt_period,
    'mail_src=s'   => \$opt_mail_src,
    'mail_dest=s'  => \$opt_mail_dest,
    'debug'        => \$opt_debug,
);

pod2usage(-verbose => 99, -sections => ['SYNOPSIS', 'OPTIONS', 'EXAMPLES'])
    if ((!$status)
    || (!defined $opt_url)
    || (!defined $opt_login)
    || (!defined $opt_password)
    || ((!defined $opt_screen) && (!defined $opt_graph_list))
    || ($opt_help));

my $period = (
    defined $opt_period
    ? (
          $opt_period =~ /^(\d+)(\w+)$/
        ? $1 * $period_letter{$2}
        : ($opt_period =~ /^(\d+)$/ ? $opt_period : '86400')
      )
    : '86400'
);

Debug("Connection to Zabbix Server %s...\n", $opt_url);
$mech->get($opt_url);

Debug("Filling Login & Password...\n");
$mech->field('name',     $opt_login,    1);
$mech->field('password', $opt_password, 1);
$mech->click_button(name => 'enter');

my $graph_files;

if (defined $opt_screen)
{
    $graph_files = Save_Graphs_From_Screen($period);
}
else
{
    $graph_files = Save_Graphs_From_List($period);
}

if ((defined $opt_mail_src) && (defined $opt_mail_dest))
{
    Debug("Sending files by mail...\n");
    my $sender = new Mail::Sender {smtp => $SMTP_SERVER, from => $opt_mail_src};
    $sender->MailFile(
        {
            to      => $opt_mail_dest,
            subject => $MAIL_SUBJECT,
            msg     => $MAIL_MESSAGE,
            file    => $graph_files
        }
    );
}

Debug("Disconnecting...\n");
$mech->get("$opt_url/index.php?reconnect=1");

=head1 CHANGELOG

0.9.3 Speed improvement

0.9.2 Graph Pictures sent by mail 

0.9.1 Fix script Description

0.9 Initial release

=head1 AUTHOR

Sebastien Thebert <sebthebert@gmail.com>

=cut
