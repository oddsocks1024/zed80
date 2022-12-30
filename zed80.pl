#!/usr/bin/perl
#
# ZED80 - Z80 Experimental Disassembler in Perl
# Version: 0.9.2
# Copyright (C) 2006-2009 Ian Chapman
#
# Based upon documentation 'Decoding Z80 Opcodes' written by Cristian Dinu
# http://www.z80.info/decoding.htm
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# 0.9.0
# Initial Release
#
# 0.9.1
# Fixed trailing NOPs.  Thanks to Charles Mullins
#
# 0.9.2
# Fixed DJNZ, passing wrong parameter. Thanks to Volker Pohlers
#
use strict;


# Config options
my $debugm = 0;          # Show debugging output
# End config options

# Globals
my $prefixmode = 0;     # Instruction prefix mode
my $ptr = -1;           # File location pointer
my $address = 0;        # Instruction address
my $dbyte = 0;          # Displacement byte holder for DDCB/FDCB prefixes.

# Lookup tables
# | is used as a delimeter to indicate substitution when in DD/FD prefix mode
my @tab_r   = ('B', 'C', 'D', 'E', '|H|', '|L|', '|(HL)|', 'A'); # 8 bit registers
my @tab_rp  = ('BC', 'DE', '|HL|', 'SP'); # Register pairs featuring SP
my @tab_rp2 = ('BC', 'DE', '|HL|', 'AF'); # Register pairs featuring AF
my @tab_cc  = ('NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M'); # Condition codes
my @tab_alu = ('ADD A,', 'ADC A,', 'SUB ', 'SBC A,', 'AND ', 'XOR ', 'OR ', 'CP '); # Arithmetic/Logic ops
my @tab_rot = ('RLC', 'RRC', 'RL', 'RR', 'SLA', 'SRA', 'SLL', 'SRL'); # Rotation/Shift Ops
my @tab_im  = ('0', '0/1', '1', '2', '0', '0/1', '1', '2'); # Interrupt modes
my @tab_bli = ([], [], [], [],
               ['LDI', 'CPI', 'INI', 'OUTI'],
               ['LDD', 'CPD', 'IND', 'OUTD'],
               ['LDIR', 'CPIR', 'INIR', 'OTIR'],
               ['LDDR', 'CPDR', 'INDR', 'OTDR']); # Block instructions

open(FH, "<", "$ARGV[0]") || die "$!";
binmode(FH);
my @finfo = stat(FH);

while ($address < $finfo[7])
{
    my $val = &read8();
    if ($debugm == 1)
    {
        print "\nX Y Z  P Q  DEC  HEX\n";
        printf("%d %d %d  %d %d  %3d  %3X\n", &findx($val), &findy($val), &findz($val), &findp($val), &findq($val), $val, $val);
    }
    &nextinst($val);
}

close (FH);

exit 0;


sub nextinst
{
    my $byte = $_[0];
    my $pbits = &findp($byte);
    my $qbits = &findq($byte);
    my $xbits = &findx($byte);
    my $ybits = &findy($byte);
    my $zbits = &findz($byte);

    # If we are currently in DD prefixmode and the next byte is DD, ED
    # or FD then it's equivalent to NONI then continue as normal
    if (($prefixmode == 0xDD) && (($byte == 0xFD) || ($byte == 0xDD) || ($byte == 0xED))) {&dumpinst('NOP        ; NONI');}
    # Check next byte to see if it's DDCB prefixed. If so, store displacement byte because it comes
    # BEFORE the opcode for these instructions.
    elsif (($prefixmode == 0xDD) && ($byte == 0xCB))
    {
        $prefixmode = 0xDDCB;
        $dbyte = &reads8();
    }
    # If we are currently in FD prefixmode and the next byte is DD, ED
    # or FD then it's equivalent to NONI then continue as normal
    elsif (($prefixmode == 0xFD) && (($byte == 0xFD) || ($byte == 0xDD) || ($byte == 0xED)))
    {
        &dumpinst('NOP        ; NONI');
    }
    # Check next byte to see if it's FDCB prefixed. If so, store displacement byte because it comes
    # BEFORE the opcode for these instructions.
    elsif (($prefixmode == 0xFD) && ($byte == 0xCB))
    {
        $prefixmode = 0xFDCB;
        $dbyte = &reads8();
    }
    elsif ($prefixmode == 0xED)
    {
        # Invalid instruction - equiv to NONI, NOP
        if (($xbits == 0) || ($xbits == 3)) {&dumpinst('NOP        ; NONI');}
        elsif ($xbits == 1) {&edx1($byte);}
        elsif ($xbits == 2) {&edx2($byte);}
    }
    elsif ($prefixmode == 0xCB)
    {
        if ($xbits == 0) {&dumpinst(sprintf('%s %s', $tab_rot[$ybits], $tab_r[$zbits]));}
        elsif ($xbits == 1) {&dumpinst(sprintf('BIT %d,%s', $ybits, $tab_r[$zbits]));}
        elsif ($xbits == 2) {&dumpinst(sprintf('RES %d,%s', $ybits, $tab_r[$zbits]));}
        elsif ($xbits == 3) {&dumpinst(sprintf('SET %d,%s', $ybits, $tab_r[$zbits]));}
    }
    elsif ($prefixmode == 0xDDCB) {&ddcb($byte);}
    elsif ($prefixmode == 0xFDCB) {&fdcb($byte);}
    else # Normal mode
    {
        if ($xbits == 0)
        {
               if ($zbits == 0) {&x0z0($byte);}
            elsif ($zbits == 1) {&x0z1($byte);}
            elsif ($zbits == 2) {&x0z2($byte);}
            elsif ($zbits == 3)
            {
                if ($qbits == 0) {&dumpinst(sprintf('INC %s', $tab_rp[$pbits]));}
                elsif ($qbits == 1) {&dumpinst(sprintf('DEC %s', $tab_rp[$pbits]));}
            }
            elsif ($zbits == 4) {&dumpinst(sprintf('INC %s', $tab_r[$ybits]));}
            elsif ($zbits == 5) {&dumpinst(sprintf('DEC %s', $tab_r[$ybits]));}
            elsif ($zbits == 6)
            {
                # Fix for instance in DD/FD prefix mode, that dumpinst can't handle
                if (($prefixmode == 0xDD) && ($ybits == 6)) {&dumpinst(sprintf('LD (IX%+d),%d', &reads8(), &read8()));}
                elsif (($prefixmode == 0xFD) && ($ybits == 6)) {&dumpinst(sprintf('LD (IY%+d),%d', &reads8(), &read8()));}
                else {&dumpinst(sprintf('LD %s,%d', $tab_r[$ybits], &read8()));}
            }
            elsif ($zbits == 7) {&x0z7($byte);}
        }
        elsif ($xbits == 1)
        {
            if (($zbits == 6) && ($ybits == 6)) {&dumpinst('HALT');}
            else {&dumpinst(sprintf('LD %s,%s', $tab_r[$ybits], $tab_r[$zbits]));}
        }
        elsif ($xbits == 2)
        {
            &dumpinst("$tab_alu[$ybits]$tab_r[$zbits]");
        }
        elsif ($xbits == 3)
        {
            if ($zbits == 0) {&dumpinst(sprintf('RET %s', $tab_cc[$ybits]));}
            elsif ($zbits == 1) {&x3z1($byte);}
            elsif ($zbits == 2) {&dumpinst(sprintf('JP %s,0x%X', $tab_cc[$ybits], &read16()));}
            elsif ($zbits == 3) {&x3z3($byte);}
            elsif ($zbits == 4) {&dumpinst(sprintf('CALL %s,0x%X', $tab_cc[$ybits], &read16()));}
            elsif ($zbits == 5) {&x3z5($byte);}
            elsif ($zbits == 6) {&dumpinst(sprintf('%s%d', $tab_alu[$ybits], &read8()));}
            elsif ($zbits == 7) {&dumpinst(sprintf('RST 0x%X', ($ybits * 8)));}
        }
    }
}


sub x0z0
{
    my $ybits = &findy($_[0]);

    if ($ybits == 0) {&dumpinst('NOP');}
    elsif ($ybits == 1) {&dumpinst('EX AF,AF\'');}
    elsif ($ybits == 2)
    {
        my $v=&reads8();
        &dumpinst(sprintf('DJNZ %d        ; EA [%d]', $v, $v+$ptr+1));
    }
    elsif ($ybits == 3)
    {
        my $v=&reads8();
        &dumpinst(sprintf('JR %d        ; EA [%d]', $v, $v+$ptr+1));
    }
    elsif ($ybits > 3)
    {
        my $v=reads8();
        &dumpinst(sprintf('JR %s,%d        ; EA [%d]', $tab_cc[$ybits-4], $v, $v+$ptr+1));
    }
}


sub x0z1
{
    my $qbits = &findq($_[0]);
    my $pbits = &findp($_[0]);

    if ($qbits == 0) {&dumpinst(sprintf('LD %s,%d', $tab_rp[$pbits], &read16()));}
    elsif ($qbits == 1) {&dumpinst(sprintf('ADD |HL|,%s', $tab_rp[$pbits]));}
}


sub x0z2
{
    my $qbits = &findq($_[0]);
    my $pbits = &findp($_[0]);

    if ($qbits == 0)
    {
        if ($pbits == 0) {&dumpinst('LD (BC),A');}
        elsif ($pbits == 1) {&dumpinst('LD (DE),A');}
        elsif ($pbits == 2) {&dumpinst(sprintf('LD (0x%X),|HL|', &read16()));}
        elsif ($pbits == 3) {&dumpinst(sprintf('LD (0x%X),A', &read16()));}
    }
    elsif ($qbits == 1)
    {
        if ($pbits == 0) {&dumpinst('LD A,(BC)');}
        elsif ($pbits == 1) {&dumpinst('LD A,(DE)');}
        elsif ($pbits == 2) {&dumpinst(sprintf('LD |HL|,(0x%X)', &read16()));}
        elsif ($pbits == 3) {&dumpinst(sprintf('LD A,(0x%X)', &read16()));}
    }
}


sub x0z7
{
    my $ybits = &findy($_[0]);

    if ($ybits == 0) {&dumpinst('RLCA');}
    elsif ($ybits == 1) {&dumpinst('RRCA');}
    elsif ($ybits == 2) {&dumpinst('RLA');}
    elsif ($ybits == 3) {&dumpinst('RRA');}
    elsif ($ybits == 4) {&dumpinst('DAA');}
    elsif ($ybits == 5) {&dumpinst('CPL');}
    elsif ($ybits == 6) {&dumpinst('SCF');}
    elsif ($ybits == 7) {&dumpinst('CCF');}
}


sub x3z1
{
    my $qbits = &findq($_[0]);
    my $pbits = &findp($_[0]);

    if ($qbits == 0) {&dumpinst(sprintf('POP %s', $tab_rp2[$pbits]));}
    elsif ($qbits == 1)
    {
           if ($pbits == 0) {&dumpinst('RET');}
        elsif ($pbits == 1) {&dumpinst('EXX');}
        # Many references use JP (HL) rather than JP HL. A 'syntax bug' of
        # sorts but JP HL is the technically correct form.
        elsif ($pbits == 2) {&dumpinst('JP HL');}
        elsif ($pbits == 3) {&dumpinst('LD SP,|HL|');}
    }
}


sub x3z3
{
    my $ybits = &findy($_[0]);

    if ($ybits == 0) {&dumpinst(sprintf('JP 0x%X', &read16()));}
    elsif ($ybits == 1) {$prefixmode = 0xCB;} # Switch to CB prefixmode
    elsif ($ybits == 2) {&dumpinst(sprintf('OUT (0x%X),A', &read8()));}
    elsif ($ybits == 3) {&dumpinst(sprintf('IN A,(0x%X)', &read8()));}
    elsif ($ybits == 4) {&dumpinst('EX (SP),HL');}
    elsif ($ybits == 5)
    {
        # This instruction is an exception to the FD/DD prefix rule, so don't
        # use || delimeters to indicate HL substitution
        &dumpinst('EX DE,HL');
    }
    elsif ($ybits == 6) {&dumpinst('DI');}
    elsif ($ybits == 7) {&dumpinst('EI');}
}


sub x3z5
{
    my $pbits = &findp($_[0]);
    my $qbits = &findq($_[0]);

    if ($qbits == 0) {&dumpinst(sprintf('PUSH %s', $tab_rp2[$pbits]));}
    elsif ($qbits == 1)
    {
        if ($pbits == 0) {&dumpinst(sprintf('CALL 0x%X', &read16()));}
        elsif ($pbits == 1) {$prefixmode = 0xDD;} # Switch to DD prefix mode
        elsif ($pbits == 2) {$prefixmode = 0xED;} # Switch to ED prefix mode
        elsif ($pbits == 3) {$prefixmode = 0xFD;} # Switch to FD prefix mode
    }
}


sub edx1
{
    my $zbits = &findz($_[0]);
    my $qbits = &findq($_[0]);
    my $pbits = &findp($_[0]);
    my $ybits = &findy($_[0]);

    if ($zbits == 0)
    {
        if ($ybits == 6) {&dumpinst('IN (C)');}  # Some docs say IN 0,(C)
        else {&dumpinst(sprintf('IN %s,(C)', $tab_r[$ybits]));} # All other values are same instruction
    }
    elsif ($zbits == 1)
    {
        if ($ybits == 6) {&dumpinst('OUT (C),0');}
        else {&dumpinst(sprintf('OUT (C),%s', $tab_r[$ybits]));} # All other values are same instruction
    }
    elsif ($zbits == 2)
    {
        if ($qbits == 0) {&dumpinst(sprintf('SBC |HL|,%s', $tab_rp[$pbits]));}
        elsif ($qbits == 1) {&dumpinst(sprintf('ADC |HL|,%s', $tab_rp[$pbits]));}
    }
    elsif ($zbits == 3)
    {
        if ($qbits == 0) {&dumpinst(sprintf('LD (0x%X),%s', &read16(), $tab_rp[$pbits]));}
        elsif ($qbits == 1) {&dumpinst(sprintf('LD %s,(0x%X)', $tab_rp[$pbits], &read16()));}
    }
    elsif ($zbits == 4) {&dumpinst('NEG');}
    elsif ($zbits == 5)
    {
        if ($ybits == 1) {&dumpinst('RETI');}
        else {&dumpinst('RETN');} # All other values are same instruction
    }
    elsif ($zbits == 6) {&dumpinst(sprintf('IM %s', $tab_im[$ybits]));}
    elsif ($zbits == 7)
    {
        if ($ybits == 0) {&dumpinst('LD I,A');}
        elsif  ($ybits == 1) {&dumpinst('LD R,A');}
        elsif  ($ybits == 2) {&dumpinst('LD A,I');}
        elsif  ($ybits == 3) {&dumpinst('LD A,R');}
        elsif  ($ybits == 4) {&dumpinst('RRD');}
        elsif  ($ybits == 5) {&dumpinst('RLD');}
        elsif  ($ybits == 6) {&dumpinst('NOP');}
        elsif  ($ybits == 7) {&dumpinst('NOP');}
    }
}


sub edx2
{
    my $zbits = &findz($_[0]);
    my $ybits = &findy($_[0]);

    if ($zbits < 4)
    {
        if ($ybits > 3) {&dumpinst($tab_bli[$ybits][$zbits]);}
        # Invalid instruction - equiv to NONI, NOP
        else {&dumpinst('NOP       ; NONI');}
    }
    # Invalid instruction - equiv to NONI, NOP
    else {&dumpinst('NOP       ; NONI');}
}


sub ddcb
{
    my $xbits = &findx($_[0]);
    my $ybits = &findy($_[0]);
    my $zbits = &findz($_[0]);

    if ($xbits == 0)
    {
        if ($zbits == 6) {&dumpinst(sprintf('%s (IX%+d)',  $tab_rot[$ybits], $dbyte));}
        else {&dumpinst(sprintf('LD %s,%s (IX%+d)', $tab_r[$zbits], $tab_rot[$ybits], $dbyte));}
    }
    elsif ($xbits == 1)
    {
        &dumpinst(sprintf('BIT %d,(IX%+d)', $ybits, $dbyte));
    }
    elsif ($xbits == 2)
    {
        if ($zbits == 6) {&dumpinst(sprintf('RES %d,(IX%+d)',  $ybits, $dbyte));}
        else {&dumpinst(sprintf('LD %s,RES %d,(IX%+d)', $tab_r[$zbits], $ybits, $dbyte));}
    }
    elsif ($xbits == 3)
    {
        if ($zbits == 6) {&dumpinst(sprintf('SET %d,(IX%+d)',  $ybits, $dbyte));}
        else {&dumpinst(sprintf('LD %s,SET %d,(IX%+d)', $tab_r[$zbits], $ybits, $dbyte));}
    }
}


sub fdcb
{
    my $xbits = &findx($_[0]);
    my $ybits = &findy($_[0]);
    my $zbits = &findz($_[0]);

    if ($xbits == 0)
    {
        if ($zbits == 6) {&dumpinst(sprintf('%s (IY%+d)',  $tab_rot[$ybits], $dbyte));}
        else {&dumpinst(sprintf('LD %s,%s (IY%+d)', $tab_r[$zbits], $tab_rot[$ybits], $dbyte));}
    }
    elsif ($xbits == 1)
    {
        &dumpinst(sprintf('BIT %d,(IY%+d)', $ybits, $dbyte));
    }
    elsif ($xbits == 2)
    {
        if ($zbits == 6) {&dumpinst(sprintf('RES %d,(IY%+d)',  $ybits, $dbyte));}
        else {&dumpinst(sprintf('LD %s,RES %d,(IY%+d)', $tab_r[$zbits], $ybits, $dbyte));}
    }
    elsif ($xbits == 3)
    {
        if ($zbits == 6) {&dumpinst(sprintf('SET %d,(IY%+d)',  $ybits, $dbyte));}
        else {&dumpinst(sprintf('LD %s,SET %d,(IY%+d)', $tab_r[$zbits], $ybits, $dbyte));}
    }
}


# Bit manipulation routines for locating opcode 'sub codes'
sub findx() {return (($_[0] & 192) >> 6);}
sub findy() {return (($_[0] & 56) >> 3);}
sub findz() {return ($_[0] & 7);}
sub findq() {return (($_[0] & 8) >> 3);}
sub findp() {return (($_[0] & 48) >> 4);}


# Read unsigned byte
sub read8
{
    $ptr++;
    read(FH, my $buffer, 1);
    return unpack('C', $buffer);
}


# Read signed byte
sub reads8
{
    $ptr++;
    read(FH, my $buffer, 1);
    return unpack('c', $buffer);
}


# Read unsigned word
sub read16
{
    $ptr = $ptr + 2;
    read(FH, my $buffer, 2);
    return unpack('v', $buffer);
}


# Output the instruction, including performing necessary register substitutions
# when in prefix modes DD/FD
sub dumpinst
{
    my $inst = $_[0];

    if ($prefixmode == 0xFD) # Handle FD prefixmode substitution here
    {
        # If the instruction contains (HL), no further substitution should be done!
        if ($inst =~ m/\|\(HL\)\|/)
        {
            my $val = &reads8();
            $inst =~ s/\|\(HL\)\|/\(IY\+$val\)/g;
        }
        else
        {
            $inst =~ s/\|HL\|/IY/g;
            $inst =~ s/\|H\|/IYH/g;
            $inst =~ s/\|L\|/IYL/g;
        }
    }
    elsif ($prefixmode == 0xDD) # Handle FD prefixmode substitution here
    {
        # If the instruction contains (HL), no further substitution should be done!
        if ($inst =~ m/\|\(HL\)\|/)
        {
            my $val = &read8();
            $inst =~ s/\|\(HL\)\|/\(IX\+$val\)/g;
        }
        else
        {
            $inst =~ s/\|HL\|/IX/g;
            $inst =~ s/\|H\|/IXH/g;
            $inst =~ s/\|L\|/IXL/g;
        }
    }

    $inst =~ s/\|//g;
    printf("0x%04X", $address);
    printf("%24s%s\n", ' ',$inst);
    $address = $ptr + 1;
    $prefixmode = 0;
}


