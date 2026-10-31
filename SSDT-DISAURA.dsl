DefinitionBlock ("", "SSDT", 2, "ASUS", "DISAURA", 0x00001000)
{
    External (_SB_.PCI0.GP17.XHC0.RHUB.PRT3, DeviceObj)

    Scope (\_SB_.PCI0.GP17.XHC0.RHUB.PRT3)
    {
        Method (_STA, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                Return (0x00)
            }
            Else
            {
                Return (0x0F)
            }
        }
    }
}
