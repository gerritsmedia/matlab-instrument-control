classdef MIC_SPTCollect < MIC_Abstract
    % MIC_SPTCollect:Matlab Instrument Class for control of 
    % Single Particle Tracking (SPT)microscopy
    %
    %This class provides date collection for:
    % Single Particle Tracking (up to two color)
    % Superresolution (up to two color)
    % Single Particle Tracking+ adding fixation buffer
    %
    % Example: obj=MIC_SPTCollect();
    % Functions: on, off, delete, shutdown, exportState, setPower 
    %
    % REQUIREMENTS: 
    %   MIC_Abstract.m
    %   MIC_Camera_Abstract.m
    %   MIC_AndorCamera.m
    %   MIC_ThorlabsIR.m
    %   MIC_LightSource_Abstract.m
    %   MIC_TcubeLaserDiode.m
    %   MIC_CrystaLaser561.m
    %   MIC_IX71Lamp.m
    %   MIC_ThorlabLED.m
    %   MIC_MCLNanoDrive
    %   MIC_SyringePump
    %   MIC_Reg3DTrans
    %   MATLAB software version R2016b or later
    %   Data Acquisition Toolbox
    %   MATLAB NI-DAQmx driver installed via the Support Package Installer
    %
    % CITATION: Sandeep Pallikkuth, Lidkelab, 2017.
     
    properties
        % Hardware objects
        CameraObj;      % Andor Camera
        IRCameraObj;    % Thorlabs IR Camera
        StageObj;       % MCL Nano Drive
        Laser638Obj;    % TCubeLaserDiode 638
        Laser561Obj;    % Crystal Laser 561
        Lamp850Obj;     % ThorlabLED Lamp for IRCamera
        LampObj;        % IX71 Lamp
        SyringePumpObj; % SyringePump for Tracking+Fixation
        R3DObj;         % Reg3DTrans class
        ActRegObj;      % Active Stabilization Object
        
        % Camera params
        ExpTime_Focus_Set=.01;          % Exposure time during focus Andor Camera
        ExpTime_Sequence_Set=.01;       % Exposure time during sequence Andor Camera
        ExpTime_Sequence_Actual=.002;
        ExpTime_Capture=.05;
        NumFrames=2000;                 % Number of frames per sequence
        NumSequences=20;                % Number of sequences per acquisition
        CameraGain=1;                   % Flag for adjusting camera Gain
        CameraEMGainHigh=200;           % High camera gain value
        CameraEMGainLow=2;              % Low camera gain value
        CameraROI=1;                    % Camera ROI (see gui for specifics)
        PixelSize;                      % Pixel size determined from calibration Andor Camera
        IRExpTime_Focus_Set=0.01;       % Exposure time during focus IR Camera
        IRExpTime_Sequence_Set=0.01;    % Exposure time during sequence IR Camera
        IRCameraROI=2;                  % IRCamera ROI (see gui for specifics)
        IRPixelSize;                    % PixelSize for IR Camera
       
        % Light source params
        Laser638Low;          % Low power 638 laser
        Laser561Low;          % Low power 561 laser
        Laser638High;         % High power 638 laser
        Laser561High;         % High power 561 laser
        LampPower;            % Power of lamp IX71
        Lamp850Power;         % Power of lamp 850
        Laser638Aq;           % Flag for using 638 laser during acquisition
        Laser561Aq;           % Flag for using 561 laser during acquisition
        LampAq;               % Flag for using lamp during acquisition
        Lamp850Aq;            % Flag for using lamp 850 during acquisition
        LampWait=0.5;         % Lamp wait time
        focus638Flag=0;       % Flag for using 638 laser during focus
        focus561Flag=0;       % Flag for using 561 laser during focus
        focusLampFlag=0;      % Flag for using Lamp IX71 during focus
        focusLamp850Flag=0;   % Flag for using Lamp 850 during focus
        
        % Other things
        SaveDir='Y:\';  % Save Directory
        BaseFileName='Cell1';   % Base File Name
        AbortNow=0;     % Flag for aborting acquisition
        RegType='None'; % Registration type, can be 'None', 'Self' or 'Ref'
        SaveFileType='mat'  %Save to *.mat or *.h5.  Options are 'mat' or 'h5'
        
        
        TimerAndor;
        TimerSyringe;
        TimerIRCamera;
        tSyring_start
        tIR_start
        tIR_end
        tAndor_start
        tAndor_end
        SyringeWaitTime
        IRSequenceLength
        sequenceType='SRCollect';  % Type of acquisition data   
                                   % 'Tracking+SRCollect' or 'SRCollect'
        ActiveRegCheck=0;
        RegCamType='Andor Camera'  % Type of Camera Bright Field Registration 
        CalFilePath
        zPosition
        MaxCC
    end
    
    properties (SetAccess = protected)
        InstrumentName = 'SPTCollect'; %Name of instrument
    end
    
    properties (Hidden)
        StartGUI=false;    % Starts GUI
    end
    
    methods
        function obj=MIC_SPTCollect()
            %Example: SPT=MIC_SPTCollect();
            obj = obj@MIC_Abstract(~nargout);
            [p,~]=fileparts(which('MIC_SPTCollect'));
            obj.CalFilePath=p;
            
            %load pixel size for Andor Camera
            if exist(fullfile(p,'SPT_AndorPixelSize.mat'),'file')
                a=load(fullfile(p,'SPT_AndorPixelSize.mat'));
                obj.PixelSize=a.PixelSize;
                clear a
            end
            
            %load pixel size for IR Camera
            if exist(fullfile(p,'SPT_IRPixelSize.mat'),'file')
                a=load(fullfile(p,'SPT_IRPixelSize.mat'));
                obj.IRPixelSize=a.PixelSize;
                clear a
            end
            
            % Initialize hardware objects
            try
                % Camera
                fprintf('Initializing Camera\n')
                obj.CameraObj=MIC_AndorCamera();
                CamSet = obj.CameraObj.CameraSetting;
                CamSet.FrameTransferMode.Bit=1;
                CamSet.FrameTransferMode.Ind=2;
                CamSet.FrameTransferMode.Desc=obj.CameraObj.GuiDialog.FrameTransferMode.Desc{2};
                CamSet.BaselineClamp.Bit=1;
                CamSet.VSSpeed.Bit=4;
                CamSet.HSSpeed.Bit=0;
                CamSet.VSAmplitude.Bit=2;
                CamSet.PreAmpGain.Bit=2;
                CamSet.EMGain.Value = obj.CameraEMGainHigh;
                obj.CameraObj.setCamProperties(CamSet);
                obj.CameraObj.setup_acquisition();
                obj.CameraObj.ReturnType='matlab';
                obj.CameraObj.DisplayZoom=4;
                fprintf('Initializing IRCamera\n')
                obj.IRCameraObj=MIC_ThorlabsIR();
                obj.IRCameraObj.DisplayZoom=1;
                % Stage
                fprintf('Initializing Stage\n')
                obj.StageObj=MIC_MCLNanoDrive();
                % Lasers
                fprintf('Initializing 638 laser\n')
                obj.Laser638Obj=MIC_TCubeLaserDiode('64844789','Current',170,0,0)
                obj.Laser638Low =0;
                obj.Laser638High =170;
                fprintf('Initializing 561 laser\n')
                % obj.Laser561Obj = MIC_CrystaLaser561('Dev1','Port0/Line0:1');
                % obj.Laser561Low= ; 
                % obj.Laser561High= ;
                % Lamp 850
                fprintf('Initializing lamp 850\n')
                obj.Lamp850Obj=MIC_ThorlabsLED('Dev1','ao1');
                obj.Lamp850Power = 30;
                % Lamp IX71
                fprintf('Initializing lamp\n')
                obj.LampObj=MIC_IX71Lamp('Dev1','ao0','Port0/Line0');
                obj.LampPower = 50;               
            catch ME
                ME
                error('hardware startup error');
            end
            
            %Set save directory
            user_name = java.lang.System.getProperty('user.name');
            timenow=clock;
         
            obj.gui();
        end
        
        function delete(obj)
            %delete all objects
            if ishandle(obj.GuiFigure)
                disp('Closing GUI...');
                delete(obj.GuiFigure)
            end
            disp('Deleting Lamp...');
            delete(obj.Lamp850Obj);
            disp('Deleting Laser 638...');
            delete(obj.LaserObj);
            disp('Deleting Stage...');
            delete(obj.StageObj);
            disp('Deleting Camera...');
            delete(obj.CameraObj);
            disp('Deleting IR Camera');
            delete(obj.IRCameraObj);
            disp('Deleting Syringe Pump')
            delete(obj.SyringePumpObj)
            disp('Turn off MCl Nanodriver and Laser 638 manually!')
            close all force;
            clear;
        end
        
        %registration channel function loadref(obj)
        function loadref(obj)
            % Load reference image file
            [a,b]=uigetfile('*.mat','Select Reference File',obj.SaveDir);
            if ~a
                return
            end
            obj.R3DObj.RefImageFile = fullfile(b,a);
            tmp=load(obj.R3DObj.RefImageFile,'Image_Reference');
            obj.R3DObj.Image_Reference=tmp.Image_Reference;
        end
        
        function takecurrent(obj)
            % captures and displays current image
            obj.LampObj.setPower(obj.LampPower);
            obj.R3DObj.getcurrentimage();
        end
        
        function align(obj)
            % Align to current reference image
            obj.set_RegCamType;
            switch obj.RegType
                case 'Self'
                    obj.takeref();
                otherwise
                    obj.loadref();
            end
            obj.LampObj.setPower(obj.LampPower);
            obj.R3DObj.align2imageFit();
        end
        
        function showref(obj)
            % Displays current reference image
            dipshow(obj.R3DObj.Image_Reference);
        end
        
        function takeref(obj)
            % Captures reference image obj.setLampPower();
            obj.R3DObj.takerefimage();
        end
        
        function saveref(obj)
            % Saves current reference image obj.R3DObj.saverefimage();
        end
        
        function focusLow(obj)
            % Focus function using the low laser settings
            CamSet=obj.CameraObj.CameraSetting;
            CamSet.EMGain.Value = obj.CameraEMGainHigh;
            obj.CameraObj.setCamProperties(CamSet);
            %        Lasers set up to 'low' power setting
            if obj.focus638Flag
                obj.Laser638Obj.setPower(obj.Laser638Low);
                obj.Laser638Obj.on;
            else
                obj.Laser638Obj.off;
            end
            %     if obj.focus561Flag
            %         obj.Laser561Obj.setPower(obj.Laser561Low);
            %         obj.Laser561Obj.on;
            %     else
            %         obj.Laser561Obj.off;
            %     end
            %
            % Aquiring and displaying images
            obj.CameraObj.ROI=obj.getROI('Andor');
            obj.CameraObj.ExpTime_Focus=obj.ExpTime_Focus_Set;
            obj.CameraObj.AcquisitionType = 'focus';
            obj.CameraObj.setup_acquisition();
            out=obj.CameraObj.start_focus();
            % Turning lasers off
            obj.Laser638Obj.off;
            %             obj.Laser561.off;
            obj.LampObj.off;
            obj.Lamp850Obj.off;
        end
        
        function focusHigh(obj)
            % Focus function using the high laser settings
            CamSet=obj.CameraObj.CameraSetting;
            CamSet.EMGain.Value = obj.CameraEMGainHigh;
            obj.CameraObj.setCamProperties(CamSet);
            %        Lasers set up to 'high' power setting
            if obj.focus638Flag
                obj.Laser638Obj.setPower(obj.Laser638High);
                obj.Laser638Obj.on;
            else
                obj.Laser638Obj.off;
            end
            %     if obj.focus561Flag
            %         obj.Laser561Obj.setPower(obj.Laser561High);
            %         obj.Laser561Obj.on;
            %     else
            %         obj.Laser561Obj.off;
            %     end
            
            % Aquiring and displaying images
            obj.CameraObj.ROI=obj.getROI('Andor');
            obj.CameraObj.ExpTime_Focus=obj.ExpTime_Focus_Set;
            obj.CameraObj.AcquisitionType = 'focus';
            obj.CameraObj.setup_acquisition();
            out=obj.CameraObj.start_focus();
            % Turning lasers off
            obj.Laser638Obj.off;
            %     obj.Laser561Obj.off;
        end
        
        function setLampPower(obj,LampPower_in)
            % sets Lamp power to input value
            if nargin<2
                obj.LampObj.setPower(obj.LampPower);
            else
                obj.LampObj.setPower(LampPower_in);
            end
            obj.LampPower=obj.LampObj.Power;
        end
        
        function focusLamp(obj)
            % Continuous display of image with lamp on. Useful for focusing
            % of the microscope.
            CamSet = obj.CameraObj.CameraSetting;
            %put Shutter back to auto
            CamSet.ManualShutter.Bit=0;
            %obj.CameraObj.setCamProperties(CamSet);
            CamSet.EMGain.Value = obj.CameraEMGainLow;
            obj.CameraObj.setCamProperties(CamSet);
            obj.LampObj.setPower(obj.LampPower);
            obj.LampObj.on;
            obj.CameraObj.ROI=obj.getROI('Andor');
            obj.CameraObj.ExpTime_Focus=obj.ExpTime_Focus_Set;
            obj.CameraObj.AcquisitionType = 'focus';
            obj.CameraObj.setup_acquisition();
            obj.CameraObj.start_focus();
            %dipshow(out);
            CamSet.EMGain.Value = obj.CameraEMGainHigh;
            obj.CameraObj.setCamProperties(CamSet);
            obj.LampObj.off;
            %           pause(obj.LampWait);
        end
        
        % Lamp 850 for IRCamera
        function focusLamp850(obj)
            % Continuous display of image with lamp on. Useful for focusing
            % of the microscopeon IRCamera
            obj.Lamp850Obj.setPower(obj.Lamp850Power);
            obj.Lamp850Obj.on;
            obj.IRCameraObj.ROI=obj.getROI('IRThorlabs');
            obj.IRCameraObj.ExpTime_Focus=obj.IRExpTime_Focus_Set;
            %             obj.IRCameraObj.AcquisitionType = 'focus';
            obj.IRCameraObj.start_focus();
            %dipshow(out);
            obj.Lamp850Obj.off;
            %           pause(obj.LampWait);
        end
        
        function set_RegCamType(obj)
            %set Registration Channel for either Andor Camera or IRCamera
            if strcmp(obj.RegCamType,'Andor Camera');
                %load pixel size for Andor Camera
                CalFileName=fullfile(obj.CalFilePath,'SPT_AndorPixelSize.mat');

                obj.R3DObj=MIC_Reg3DTrans(obj.CameraObj,obj.StageObj,obj.LampObj,CalFileName);
                obj.R3DObj.LampPower=obj.LampPower;
                obj.R3DObj.LampWait=2.5;
                obj.R3DObj.CamShutter=true;
                obj.R3DObj.ChangeEMgain=true;
                obj.R3DObj.EMgain=2;
                obj.R3DObj.ChangeExpTime=true;
                obj.R3DObj.ExposureTime=0.01;
          
            elseif strcmp(obj.RegCamType,'IRCamera')
                %load pixel size for IR Camera
                CalFileName=fullfile(obj.CalFilePath,'SPT_IRPixelSize.mat');
                
                obj.R3DObj=MIC_Reg3DTrans(obj.IRCameraObj,obj.StageObj,obj.Lamp850Obj,CalFileName);
                obj.R3DObj.LampPower=obj.Lamp850Power;
                obj.R3DObj.LampWait=2.5;
                obj.R3DObj.CamShutter=false;
                obj.R3DObj.ChangeEMgain=false;
                obj.R3DObj.ChangeExpTime=true;
                obj.R3DObj.ExposureTime=0.01;
            end
        end
        
        function StartSequence(obj,guihandles)
            %collect superresolution data
            
            %create save folder and filenames
            if ~exist(obj.SaveDir,'dir');mkdir(obj.SaveDir);end
            
            %delete all timers
            delete(timerfindall)
            timenow=clock;
            s=['-' num2str(timenow(1)) '-' num2str(timenow(2))  '-' num2str(timenow(3)) '-' num2str(timenow(4)) '-' num2str(timenow(5)) '-' num2str(round(timenow(6)))];
            
            %first take a reference image or align to image
            obj.LampObj.setPower(obj.LampPower);
            
            %set Registration Channel for one of the camera
            obj.set_RegCamType();
            switch obj.RegType
                case 'Self' %take and save the reference image
                    obj.R3DObj.takerefimage();
                    f=fullfile(obj.SaveDir,[obj.BaseFileName s '_ReferenceImage']);
                    Image_Reference=obj.R3DObj.Image_Reference; %#ok<NASGU>
                    save(f,'Image_Reference');
                case 'Ref'
                    if isempty(obj.R3DObj.Image_Reference)
                        error ('Load a reference image!')
                    end
            end
            
            %define IRCameraObj from different classes if SPT+SR is running
            if strcmp(obj.sequenceType,'Tracking+SRCollect');
                if ~isempty(obj.IRCameraObj)
                    obj.IRCameraObj.delete;
                end
                obj.IRCameraObj=MIC_IRSyringPump();
                obj.IRCameraObj.DisplayZoom=1;
                obj.ActiveRegCheck=0;
            end
%             if strcmp(obj.sequenceType,'SRCollect');
%                 if ~isempty(obj.IRCameraObj)
%                     obj.IRCameraObj.delete;
%                     obj.IRCameraObj=[];
%                 end
%                 obj.IRCameraObj=MIC_ThorlabsIR();
%                 obj.IRCameraObj.DisplayZoom=1;
%             end
            %
            %set Active Stabilization
            if obj.ActiveRegCheck==1
                %setup Lamp850
                %Active Stabilization
                obj.ActRegObj=MIC_ActiveReg3D_SPT(obj.IRCameraObj,obj.StageObj);
                obj.ActRegObj.PixelSize=obj.IRPixelSize;
                obj.Lamp850Obj.setPower(obj.Lamp850Power);
                obj.Lamp850Obj.on
                obj.IRCameraObj.ROI=obj.getROI('IRThorlabs');
                obj.ActRegObj.takeRefImageStack;
                obj.ActRegObj.X_Current=[];
                obj.ActRegObj.Y_Current=[];
                obj.ActRegObj.Z_Current=[];
            end
            
            switch obj.SaveFileType
                case 'mat'
                case 'h5'
                    FileH5=fullfile(obj.SaveDir,[obj.BaseFileName s '.h5']);
                    MIC_H5.createFile(FileH5);
                    MIC_H5.createGroup(FileH5,'Data');
                    MIC_H5.createGroup(FileH5,'Data/Channel01');
                otherwise
                    error('StartSequence:: unknown file save type')
            end
            
                            MaxCC=[];
Image_BF=[];
            %loop over sequences
            for nn=1:obj.NumSequences
                if obj.AbortNow; obj.AbortNow=0; break; end
                
                nstring=strcat('Acquiring','...',num2str(nn),'/',num2str(obj.NumSequences));
                set(guihandles.Button_ControlStart, 'String',nstring,'Enable','off');
                
                %align to image
                switch obj.RegType
                    case 'None'
                    otherwise
                        obj.R3DObj.align2imageFit();
                        Image_BF{nn}=obj.R3DObj.Image_Current;
                        MaxCC(nn)=obj.R3DObj.maxACmodel;
                end
                
                %Setup laser for aquisition
                if obj.Laser638Aq
                    obj.Laser638Obj.setPower(obj.Laser638High);
                    obj.Laser638Obj.on;
                end
                if obj.Laser561Aq
                    obj.Laser561Obj.setPower(obj.Laser561High);
                    obj.Laser561Obj.on;
                end
                
                if obj.LampAq
                    obj.LampObj.setPower(obj.LampPower);
                    obj.LampObj.on;
                end
                
                if obj.Lamp850Aq
                    obj.Lamp850Obj.setPower(obj.LampPower);
                    obj.Lamp850Obj.on;
                end
                
                %Setup Camera
                CamSet = obj.CameraObj.CameraSetting;
                CamSet.EMGain.Value = obj.CameraEMGainHigh;
                switch obj.CameraGain %??
                    case 1 %Low pre-amp gain
                        CamSet.PreAmpGain.Bit=2;
                    case 2 %high pre-amp gain
                        
                end
                obj.CameraObj.setCamProperties(CamSet);
                obj.CameraObj.ExpTime_Sequence=obj.ExpTime_Sequence_Set;
                obj.CameraObj.SequenceLength=obj.NumFrames;
                obj.CameraObj.ROI=obj.getROI('Andor');
                fprintf('EM Gain\n')
                obj.CameraObj.CameraSetting.EMGain
                CamSet.FrameTransferMode.Ind=2;
                obj.CameraObj.setCamProperties(CamSet);
                fprintf('Frame mode\n')
                obj.CameraObj.CameraSetting.FrameTransferMode
                %Collect
                % For SPT microscope there are three options for imaging:
                % 1)'SRCollect'=normal SRCollect: for supperresolution and tracking
                % 2)'Tracking+SRCollect'= for tracking+superresolution in consecutive order
                % using SyringePump
                % 3)'TwoColorTracking'= Use two EMCCD cameras and two
                % lasers (638 nm, 561 nm) for tracking or superresolution
                
                %obj.sequenceType='SRCollect'
                if  strcmp(obj.sequenceType,'SRCollect')
                    
                    %------------------------------------------IR capture version 2---------------------------------
                    if obj.ActiveRegCheck==1
                        IRWaitTime=1;
                        numf=floor(obj.ExpTime_Sequence_Set*obj.NumFrames)./IRWaitTime;
                        TimerIR=timer('StartDelay',0,'period',IRWaitTime,'TasksToExecute',numf,'ExecutionMode','fixedRate');
                        
                        if numf>1
                            IRsaveDir=[obj.SaveDir,obj.BaseFileName,s,'\'];
                            if ~exist(IRsaveDir,'dir');mkdir(IRsaveDir);end
                            TimerIR.TimerFcn={@IRCaptureTimerFcnV1,obj.ActRegObj,IRsaveDir,'IRImage-'};
                            obj.tIR_start=clock;
                            start(TimerIR);
                        else
                            if nn==1
                                proceedstr=questdlg('Sequence duration is less than 1 s, do you want to continue without active stabilization?','Warning',...
                                    'Yes','No','No');
                                if strcmp('No',proceedstr)
                                    return;
                                end
                            end
                        end
                        obj.tIR_end=clock;
                        
                    end
                    
                    
                    % collect
                    obj.tAndor_start=clock;
                    zPosition(nn)=obj.StageObj.Position(3);
                    sequence=obj.CameraObj.start_sequence();
                    obj.tAndor_end=clock;
                    %-----------------------------------------wait IR camera version 2------------
                    if obj.ActiveRegCheck==1
                        st=TimerIR.Running;
                        while(strcmp(st,'on'))
                            st=TimerIR.Running;
                            pause(0.1);
                        end
                        delete(TimerIR);
                    end
                    
                    
                    
                elseif strcmp(obj.sequenceType,'Tracking+SRCollect');
                    
                    %Setup IRCamera
                    obj.IRCameraObj.ROI=obj.getROI('IRThorlabs')
                    obj.IRCameraObj.ExpTime_Sequence=obj.IRExpTime_Sequence_Set;
                    % time should be long to cover all process after
                    % syringe pump for 5min=0.01*30000
                    obj.IRCameraObj.SequenceLength=obj.ExpTime_Sequence_Set*obj.NumFrames+90
                    obj.IRCameraObj.KeepData=1; % image is saved in IRCamera.Data
                    
                    %set timer for IRcamera
                    obj.TimerIRCamera=timer('StartDelay',0.5);
                    obj.TimerIRCamera.TimerFcn={@IRCamerasequenceTimerFcn,obj.IRCameraObj}
                    
                    %set timer for SyringePump
                    obj.SyringeWaitTime=obj.ExpTime_Sequence_Set*obj.NumFrames+15;
                    obj.IRCameraObj.SPwaitTime=obj.SyringeWaitTime
                    obj.tIR_start=clock;
                    start(obj.TimerIRCamera);
                    obj.tAndor_start=clock;
                    sequence=obj.CameraObj.start_sequence();
                    obj.tAndor_end=clock;
                    fprintf('IRCamera is finished...\n')
                    
                    %Turn off Syringe Pump
                    obj.TimerSyringe=clock;
                    obj.IRCameraObj.SP.stop
                    fprintf('Syringe Pump is stopped\n')
                    
                    %                     %clear IRCamera
                    %                     obj.IRCameraObj.delete();
                    %                     obj.IRCameraObj=[];
                end
                
                %Turn off Laser
                obj.Laser638Obj.off;
                %         obj.Laser561Obj.off;
                obj.LampObj.off;
                obj.Lamp850Obj.off;
                
                if isempty(sequence)
                    errordlg('Window was closed before capture complete.  No Data Saved.','Capture Failed');
                    return;
                end
                
                %Save
                switch obj.SaveFileType
                    case 'mat'
                        fn=fullfile(obj.SaveDir,[obj.BaseFileName '#' num2str(nn,'%04d') s]);
                       if strcmp(obj.sequenceType,'Tracking+SRCollect')
                        [Params IRData]=exportState(obj); %#ok<NASGU>
                        save(fn,'sequence','Params','IRData');
                       else 
                           [Params]=exportState(obj); %#ok<NASGU>
                        save(fn,'sequence','Params','zPosition','MaxCC','Image_BF');
                       end
                    case 'h5' %This will become default
                        S=sprintf('Data%04d',nn)
                        MIC_H5.writeAsync_uint16(FileH5,'Data/Channel01',S,sequence);
                    otherwise
                        error('StartSequence:: unknown SaveFileType')
                end
            end
            
            switch obj.SaveFileType
                case 'mat'
                    %Nothing to do
                case 'h5' %This will become default
                    S='MIC_TIRF_SRcollect';
                    MIC_H5.createGroup(FileH5,S);
                    obj.save2hdf5(FileH5,S);  %Not working yet
                otherwise
                    error('StartSequence:: unknown SaveFileType')
            end
            
        end
        
        
        function ROI=getROI(obj,CameraIndex)
            %these could be set from camera size;
            if nargin <2
                error('Choose type of Camera')
            end
            %             switch CameraIndex
            %                 case 'IRThorlabs'
            %                     DimX=obj.IRCameraObj.XPixels;
            %                     DimY=obj.IRCameraObj.YPixels;
            %                     cameraROI=obj.IRCameraROI;
            %                 case 'Andor'
            %                     DimX=obj.CameraObj.XPixels;
            %                     DimY=obj.CameraObj.YPixels;
            %                     cameraROI=obj.CameraROI;
            %             end
            if strcmp(CameraIndex,'Andor')
                DimX=obj.CameraObj.XPixels;
                DimY=obj.CameraObj.YPixels;
                cameraROI=obj.CameraROI;
                switch cameraROI
                    
                    case 1
                        ROI=[1 DimX 1 DimY]; %full
                    case 2
                        ROI=[1 round(DimX/2) 1 DimY];%left
                    case 3
                        ROI=[round(DimX/2)+1 DimX 1 DimY];%right
                    case 4  %Center Left
                        ROI=[1 round(DimX/2) round(DimX/4)+1 round(DimX*3/4)];
                    case 5
                        ROI=[round(DimX/2)+1 DimX round(DimX/4)+1 round(DimX*3/4)];% right center
                    case 6
                        ROI=[1 DimX round(DimX/4)+1 round(DimX*3/4)];% center horizontally
                    case 7
                        ROI=[1 DimX round(DimX*3/8)+1 round(DimX*5/8)];% center horizontally half
                    otherwise
                        error('SRcollect: ROI not found')
                end
            elseif strcmp(CameraIndex,'IRThorlabs')
                DimX=obj.IRCameraObj.XPixels;
                DimY=obj.IRCameraObj.YPixels;
                cameraROI=obj.IRCameraROI;
                
                switch cameraROI
                    case 1
                        ROI=[1 DimX 1 DimY]; %full
                    case 2   %Center for SPT setup 350*350
                        ROI=[468 817 420 769];
                    case 3   %Center for SPT setup 256*256
                        % This was chosen manually
                        ROI=[515 770 467 722];
                    case 4   %Center for SPT setup 128*128
                        % This was chosen manually
                        ROI=[579 706 532 659];
                end
                
            end
        end
        
        function [Attributes,Data,Children] = exportState(obj)
            % exportState Exports current state of all hardware objects and
            % SRcollect settings
            
            % Children
            [Children.Camera.Attributes,Children.Camera.Data,Children.Camera.Children]=...
                obj.CameraObj.exportState();
            
            [Children.IRCameraObj.Attributes,Children.IRCameraObj.Data,Children.IRCameraObj.Children]=...
                obj.IRCameraObj.exportState();
            
            [Children.Stage.Attributes,Children.Stage.Data,Children.Stage.Children]=...
                obj.StageObj.exportState();
            
            [Children.Laser638Obj.Attributes,Children.Laser638Obj.Data,Children.Laser638Obj.Children]=...
                obj.Laser638Obj.exportState();
            
            %     [Children.Laser561Obj.Attributes,Children.Laser561Obj.Data,Children.Laser561Obj.Children]=...
            %         obj.Laser561Obj.exportState();
            %
            [Children.Lamp.Attributes,Children.Lamp.Data,Children.Lamp.Children]=...
                obj.LampObj.exportState();
            
            [Children.Lamp850.Attributes,Children.Lamp850.Data,Children.Lamp850.Children]=...
                obj.Lamp850Obj.exportState();
            if isfield(obj,'Reg3D')
                [Children.Reg3D.Attributes,Children.Reg3D.Data,Children.Reg3D.Children]=...
                    obj.R3DObj.exportState();
            end
            
            
            % Our Properties
            Attributes.ExpTime_Focus_Set = obj.ExpTime_Focus_Set;
            Attributes.ExpTime_Sequence_Set = obj.ExpTime_Sequence_Set;
            Attributes.NumFrames = obj.NumFrames;
            Attributes.NumSequences = obj.NumSequences;
            Attributes.CameraGain = obj.CameraGain;
            Attributes.CameraEMGainHigh = obj.CameraEMGainHigh;
            Attributes.CameraEMGainLow = obj.CameraEMGainLow;
            Attributes.CameraROI = obj.getROI('Andor');
            Attributes.CameraPixelSize=obj.PixelSize;
            Attributes.IRExpTime_Focus_Set=obj.IRExpTime_Focus_Set;
            Attributes.IRExpTime_Sequence_Set=obj.IRExpTime_Sequence_Set;
            Attributes.IRCameraROI=obj.getROI('IRThorlabs');
            
            Attributes.SaveDir = obj.SaveDir;
            Attributes.RegType = obj.RegType;
            
            % light source properties
            Attributes.Laser638Low = obj.Laser638Low;
            %     Attributes.Laser561Low = obj.Laser561Low;
            Attributes.Laser638High = obj.Laser638High;
            %     Attributes.Laser561High = obj.Laser561High;
            Attributes.LampPower = obj.LampPower;
            Attributes.Lamp850Power = obj.Lamp850Power;
            %     Attributes.Laser561Aq = obj.Laser561Aq;
            Attributes.Laser638Aq = obj.Laser638Aq;
            Attributes.LampAq = obj.LampAq;
            Attributes.Lam850pAq = obj.Lamp850Aq;
            
            Data=obj.IRCameraObj.Data;
        end
    end
    
    methods (Static)
        
        function State = unitTest()
            State = obj.exportState();
        end
        
    end
end


