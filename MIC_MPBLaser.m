classdef MIC_MPBLaser < MIC_LightSource_Abstract
    %   MIC_MPBLaser Matlab Instrument Control Class for the MPB-laser.
    %   This class controls the PMB-laser.
    %   The constructor do not need any info about the port, it will
    %   automatically find the available port to communicate with the
    %   laser.
    %   Because it is trying to find the port to communicate with the
    %   instrument it will send messages to different ports and if the port
    %   is not giving any feedback, which means that it's not the port that
    %   we are looking for, it will give a timeout warning which can be
    %   neglected.
    %   
    %   REQUIRES: 
    %   MIC_Abstract.m
    %   MIC_LightSource_Abstract.m
    %   MATLAB 2014 or higher
    %   Install the software coming with the laser.
    
    properties (SetAccess=protected)
        InstrumentName='MPBLaser647'; %Name of the instrument.
    end
    
    properties (SetAccess=protected)
        Power; %This is the power read from the instrument.
        PowerUnit = 'mW'; %This gives the unit of the power.
        MinPower; %Minimum power for this laser.
        MaxPower; %Maximum power for this laser.
        IsOn=0; %1 indicates that the laser is on and 0 means off.
    end
    
    properties
        SerialObj; %info of the port associated with this instrument.
        SerialNumber; %serial number of the laser.
        
        WaveLength = 637; %Wavelength of the laser.
        Port; %the name of the port that is used to communicate with the laser.
        StartGUI=false; %true will popup the gui automatically and false value makes the user to open the gui manually.
    end

    methods (Static) 
        
        function obj=MIC_MPBLaser
            %This is the constructor. It iteratively go through all the ports, opens them and then
            %sends a message to them to see if we get any responce. Furthermore, it makes an object of the
            %class and sets some of the properties.
            
            obj@MIC_LightSource_Abstract(~nargout);
            
            for ii = 1:10
                %This for-loop goes through all the ports, open them and
                %send a message to the in order to see which port responds
                %back. The port that gives a feedback is the one that this
                %laser is connected to.
                s=sprintf('COM%d',ii);
                Ac = serial(s);
                Ac.Terminator='CR';
                try 
                    fopen(Ac);
                    fprintf(Ac,'GETPOWERSETPTLIM 0');
                    Limits=fscanf(Ac);
                     if ~isempty(Limits)
                         obj.Port=s;
                        break;
                     else
                         fclose(Ac);
                         delete(Ac);
                     end
                catch
                    fclose(Ac);
                    delete(Ac);
                end
                
                
            end
            obj.SerialObj=Ac;
            obj.WaveLength=647; 
            Limits = sscanf(Limits,'%f');
            obj.MinPower=(Limits(1));
            obj.MaxPower=(Limits(2));
            obj.SerialNumber=obj.send('GETSN');
            obj.Power=str2double(obj.send('GETPOWER 0')); %Gets APC Mode set point
            obj.send('POWERENABLE 1'); %Sets APC Mode
        end
        
         function unitTest()
             %unitTest() goes through each method of the class and see if they work properly. 
             %To run this method and test the class just type
             %"MIC_MPBLaser.unitTest()" in the command line.
           try
               TestObj=MIC_MPBLaser();
               fprintf('The object was successfully created.\n');
               on(TestObj);
               fprintf('The laser is on.\n');
               setPower(TestObj,TestObj.MaxPower/2); pause(1)
               fprintf('The power is successfully set to half of the max power.\n');
                setPower(TestObj,TestObj.Minpower);
               fprintf('The power is successfully set to the MinPower.\n');
               off(TestObj);
               fprintf('The laser is off.\n');
               delete(TestObj);
               fprintf('The communication port is deleted.\n');
               fprintf('The class is successfully tested :)\n');
           catch E
               fprintf('Sorry, an error occured :(\n');
               error(E.message);
           end
         end
        
    end
    methods
        
        function Reply=send(obj,Message)
            %This method is being called inside other methods to send a
            %message and reading the feedback of the instrument.
            fprintf(obj.SerialObj,Message);
            Reply=fscanf(obj.SerialObj);
            Reply=Reply(4:end);
        end
        
        
        function setPower(obj,Power_mW)
            %This method gets the desired power as an input and sets the
            %laser power to that.
            if Power_mW<obj.MinPower
                error('MPBLaser: Set_Power: Requested Power Below Minimum')
            end
            
            if Power_mW>obj.MaxPower
                error('MPBLaser: Set_Power: Requested Power Above Maximum')
            end
            
            S=sprintf('SETPOWER 0 %g',Power_mW);
            obj.send(S);
            obj.Power=str2double(obj.send('GETPOWER 0'));
            %fprintf('MPB Laser Power Set to %g mW\n',obj.Power)
        end
        
        function on(obj)
            %This method turns the laser on.
            obj.send('SETLDENABLE 1');
            if str2double(obj.send('GETLDENABLE'))
                obj.IsOn=1;
            else
                obj.IsOn=0;
            end
        end
        
        function off(obj)
            %This method turns the laser off.
            obj.send('SETLDENABLE 0');
            obj.IsOn=0;
        end
        
        function State=exportState(obj)   
            %This is an abstract method in super-super-class.
            %It exports All Non-Transient Properties in a Structure called
            %satet.
            State.Power=obj.Power;
            State.IsOn=obj.IsOn;
            State.LaserStateText=obj.LaserStateText;
            State.WaveLength=obj.WaveLength;
            State.MinPower=obj.MinPower;
            State.maxpower=obj.MaxPower;
            State.SerialNumber=obj.SerialNumber;
        end
        
        function shutdown(obj)
            %This function is called in the destructor to delete the communication port.
            Aa=instrfind('port',obj.Port);
            for ii=1:length(Aa)
               delete(Aa(ii)); 
            end
        end
        
        function delete(obj)
            %This is the destructor that call the shutdown() function to
            %delete the communication port and also deleting the object
            %created.
            obj.shutdown();
            delete(obj.GuiFigure);
            clear obj;
            
        end
        
    end
    
end
